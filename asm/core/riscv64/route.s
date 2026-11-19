/*
 * lantern_api_route, RISC-V: in the common object. Requirements: docs/reference/beacon-api.md.
 * Uses http_find, http_trim and http_same of http.s.
 */

    API_ROUTE_DATA
    .p2align 3
route_base58:                               # the base58btc alphabet, a bit each
    .quad   0x03fe000000000000, 0x07ffeffe07ff7dfe
route_t_json:
    .ascii  "application/json"
.set route_t_json_len, 16
route_t_ssz:
    .ascii  "application/octet-stream"
.set route_t_ssz_len, 24
route_t_any_application:
    .ascii  "application/*"
.set route_t_any_application_len, 13
route_t_any:
    .ascii  "*/*"
.set route_t_any_len, 3

/* reg = the value of the hex digit in reg (either case), else branch to bad. Uses tmp and tmp2. */
.macro ROUTE_HEX reg, tmp, tmp2, bad
    addi    \tmp, \reg, -48
    sltiu   \tmp2, \tmp, 10
    bnez    \tmp2, 77f
    ori     \tmp, \reg, 0x20
    addi    \tmp, \tmp, -97
    sltiu   \tmp2, \tmp, 6
    beqz    \tmp2, \bad
    addi    \tmp, \tmp, 10
77: mv      \reg, \tmp
.endm

/* L0: a0 = 1 when each % of the a1 bytes at a0 is followed by two hex digits, else 0. A leaf. Uses t0-t5. */
LOCAL_FUNCTION route_pct_ok
    UNWIND_END_PROLOGUE
    li      t0, 0
    li      t5, '%'
1:  bgeu    t0, a1, 9f
    add     t1, a0, t0
    lbu     t2, 0(t1)
    addi    t0, t0, 1
    bne     t2, t5, 1b
    addi    t3, t0, 2
    bgtu    t3, a1, 8f
    lbu     t2, 1(t1)
    ROUTE_HEX t2, t3, t4, 8f
    lbu     t2, 2(t1)
    ROUTE_HEX t2, t3, t4, 8f
    addi    t0, t0, 2
    j       1b
8:  li      a0, 0
    ret
9:  li      a0, 1
    ret
END_FUNCTION route_pct_ok

/*
 * L0: the a1 bytes at a0, percent-decoded (each % is followed by two hex digits), to a2: at most a3
 * bytes written; a0 = the decoded length, which may pass a3. A leaf. Uses t0-t6.
 */
LOCAL_FUNCTION route_decode
    UNWIND_END_PROLOGUE
    li      t0, 0
    li      t1, 0
    li      t5, '%'
1:  bgeu    t0, a1, 9f
    add     t2, a0, t0
    lbu     t3, 0(t2)
    addi    t0, t0, 1
    bne     t3, t5, 2f
    lbu     t3, 1(t2)
    ROUTE_HEX t3, t4, t6, 9f
    lbu     t2, 2(t2)
    ROUTE_HEX t2, t4, t6, 9f
    slli    t3, t3, 4
    or      t3, t3, t2
    addi    t0, t0, 2
2:  bgeu    t1, a3, 3f
    add     t2, a2, t1
    sb      t3, 0(t2)
3:  addi    t1, t1, 1
    j       1b
9:  mv      a0, t1
    ret
END_FUNCTION route_decode

/*
 * L0: one item of a list value: the bytes at a0 from index a1 to index a2, percent-decoded, up to
 * the first decoded `,`, to a3 with at most a4 bytes written. a0 = the index after the item and its
 * comma, a1 = the item's decoded length (it may pass a4), a2 = 1 when a comma ended it. A leaf. Uses a5, t0-t6.
 */
LOCAL_FUNCTION route_next_item
    UNWIND_END_PROLOGUE
    li      t1, 0
    li      a5, 0
    li      t5, '%'
1:  bgeu    a1, a2, 9f
    add     t2, a0, a1
    lbu     t3, 0(t2)
    addi    a1, a1, 1
    bne     t3, t5, 2f
    lbu     t3, 1(t2)
    ROUTE_HEX t3, t4, t6, 9f
    lbu     t2, 2(t2)
    ROUTE_HEX t2, t4, t6, 9f
    slli    t3, t3, 4
    or      t3, t3, t2
    addi    a1, a1, 2
2:  li      t4, ','
    beq     t3, t4, 8f
    bgeu    t1, a4, 3f
    add     t2, a3, t1
    sb      t3, 0(t2)
3:  addi    t1, t1, 1
    j       1b
8:  li      a5, 1
9:  mv      a0, a1
    mv      a1, t1
    mv      a2, a5
    ret
END_FUNCTION route_next_item

/* L0: the a1 bytes at a0 as a decimal number below 2^64: a0 = 0 and a1 = its value, else a0 = 1. A leaf. Uses t0-t4. */
LOCAL_FUNCTION route_number
    UNWIND_END_PROLOGUE
    beqz    a1, 8f
    li      t0, 0
    li      t1, 0
    li      t4, 10
1:  bgeu    t1, a1, 9f
    add     t2, a0, t1
    lbu     t2, 0(t2)
    addi    t2, t2, -48
    bgeu    t2, t4, 8f
    mulhu   t3, t0, t4
    bnez    t3, 8f
    mul     t0, t0, t4
    add     t0, t0, t2
    bltu    t0, t2, 8f
    addi    t1, t1, 1
    j       1b
8:  li      a0, 1
    ret
9:  mv      a1, t0
    li      a0, 0
    ret
END_FUNCTION route_number

/* L0: the a1 bytes at a0 as 0x and the hex of a2 bytes: a0 = 0 and the bytes at a3, else a0 = 1. A leaf. Uses t0-t3. */
LOCAL_FUNCTION route_hex
    UNWIND_END_PROLOGUE
    slli    t0, a2, 1
    addi    t0, t0, 2
    bne     a1, t0, 8f
    lbu     t0, 0(a0)
    li      t1, '0'
    bne     t0, t1, 8f
    lbu     t0, 1(a0)
    li      t1, 'x'
    bne     t0, t1, 8f
    addi    a0, a0, 2
1:  beqz    a2, 9f
    lbu     t0, 0(a0)
    ROUTE_HEX t0, t2, t3, 8f
    lbu     t1, 1(a0)
    ROUTE_HEX t1, t2, t3, 8f
    slli    t0, t0, 4
    or      t0, t0, t1
    sb      t0, 0(a3)
    addi    a0, a0, 2
    addi    a3, a3, 1
    addi    a2, a2, -1
    j       1b
8:  li      a0, 1
    ret
9:  li      a0, 0
    ret
END_FUNCTION route_hex

/* L0: the word of api_words for parameter a0 that is the a2 bytes at a1: a0 = 1 and a1 = its value, else a0 = 0. A leaf. Uses t0-t6. */
LOCAL_FUNCTION route_word
    UNWIND_END_PROLOGUE
    lla     t0, api_words
    lla     t1, api_word_text
    li      t2, API_WORDS
1:  beqz    t2, 8f
    ld      t3, 0(t0)
    bne     t3, a0, 5f
    ld      t3, 16(t0)
    bne     t3, a2, 5f
    ld      t3, 8(t0)
    add     t3, t1, t3
    li      t4, 0
2:  bgeu    t4, a2, 7f
    add     t5, t3, t4
    lbu     t5, 0(t5)
    add     t6, a1, t4
    lbu     t6, 0(t6)
    bne     t5, t6, 5f
    addi    t4, t4, 1
    j       2b
7:  ld      a1, 24(t0)
    li      a0, 1
    ret
5:  addi    t0, t0, 32
    addi    t2, t2, -1
    j       1b
8:  li      a0, 0
    ret
END_FUNCTION route_word

/*
 * L0: whether the a1 bytes at a0, a path whose percent-encoding is good, match the template of a3
 * bytes at a2: a0 = 1 or 0. Each parameter segment goes to the list at a4: its count, then for each
 * its API_PARAM_*, start and end in the path. A leaf. Uses a5, a6, t0-t6.
 */
LOCAL_FUNCTION route_match
    UNWIND_END_PROLOGUE
    li      t0, 1
    li      t1, 1
    li      t2, 0
    sd      zero, 0(a4)
1:  bgeu    t1, a3, 8f
    add     t5, a2, t1
    lbu     t3, 0(t5)
    li      t5, 0x20
    bgeu    t3, t5, 3f
    mv      t4, t0                          # a parameter: up to the next /
    li      a5, '/'
2:  bgeu    t0, a1, 21f
    add     t5, a0, t0
    lbu     t5, 0(t5)
    beq     t5, a5, 21f
    addi    t0, t0, 1
    j       2b
21: beq     t0, t4, 7f
    li      t5, 24
    mul     t5, t2, t5
    add     t5, a4, t5
    sd      t3, 8(t5)
    sd      t4, 16(t5)
    sd      t0, 24(t5)
    addi    t2, t2, 1
    sd      t2, 0(a4)
    addi    t1, t1, 1
    j       1b
3:  li      t5, '/'                         # a separator: a / of the path itself
    bne     t3, t5, 4f
    bgeu    t0, a1, 7f
    add     t6, a0, t0
    lbu     t6, 0(t6)
    bne     t6, t5, 7f
    addi    t0, t0, 1
    addi    t1, t1, 1
    j       1b
4:  bgeu    t0, a1, 7f                      # a fixed byte: the path's next decoded byte
    add     t6, a0, t0
    lbu     t4, 0(t6)
    addi    t0, t0, 1
    li      t5, '%'
    bne     t4, t5, 5f
    lbu     t4, 1(t6)
    ROUTE_HEX t4, t5, a5, 7f
    lbu     a6, 2(t6)
    ROUTE_HEX a6, t5, a5, 7f
    slli    t4, t4, 4
    or      t4, t4, a6
    addi    t0, t0, 2
5:  bne     t4, t3, 7f
    addi    t1, t1, 1
    j       1b
8:  sub     a0, t0, a1
    seqz    a0, a0
    ret
7:  li      a0, 0
    ret
END_FUNCTION route_match

/*
 * L0: the a3 decoded bytes at a2 as a value of parameter a1, into ApiRoute a0; an item of a list
 * goes to the 64 bytes at a4. a0 = 0, or 1 when the value breaks its type.
 * s1 out, s2 the parameter, s3 bytes, s4 length, s5 the item's place, s6 the field.
 */
LOCAL_FUNCTION route_value
    ENTER 0
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    mv      s5, a4
    lla     t0, api_params
    slli    t1, s2, 5
    add     t0, t0, t1
    ld      s6, 24(t0)
    ld      t0, 16(t0)
    li      t1, API_KIND_NUMBER
    beq     t0, t1, 10f
    li      t1, API_KIND_STATE_ID
    beq     t0, t1, 11f
    li      t1, API_KIND_BLOCK_ID
    beq     t0, t1, 11f
    li      t1, API_KIND_BLOCK_ROOT
    beq     t0, t1, 13f
    li      t1, API_KIND_VALIDATOR
    beq     t0, t1, 14f
    li      t1, API_KIND_ID_LIST
    beq     t0, t1, 15f
    li      t1, API_KIND_PEER_ID
    beq     t0, t1, 16f
    li      t1, API_KIND_SYNCING
    beq     t0, t1, 17f
    li      t1, API_KIND_ROOT
    beq     t0, t1, 18f
    li      t1, API_KIND_RANDAO
    beq     t0, t1, 19f
    li      t1, API_KIND_GRAFFITI
    beq     t0, t1, 20f
    li      t1, API_KIND_FLAG
    beq     t0, t1, 21f
    li      t1, API_KIND_WORD
    beq     t0, t1, 22f
    li      t1, API_KIND_SET
    beq     t0, t1, 23f
    li      t1, API_KIND_INDEX_LIST
    beq     t0, t1, 24f
    li      t1, API_KIND_HASH_LIST
    beq     t0, t1, 25f
    j       98f
10: mv      a0, s3                          # a number, to its field
    mv      a1, s4
    call    route_number
    bnez    a0, 98f
    add     t0, s1, s6
    sd      a1, 0(t0)
    j       90f
11: mv      a0, s2                          # state_id, block_id: a word, a slot or a root
    mv      a1, s3
    mv      a2, s4
    call    route_word
    beqz    a0, 12f
    sd      a1, ApiRoute_id_kind(s1)
    j       90f
12: mv      a0, s3
    mv      a1, s4
    call    route_number
    bnez    a0, 13f
    li      t0, API_ID_SLOT
    sd      t0, ApiRoute_id_kind(s1)
    sd      a1, ApiRoute_id_slot(s1)
    j       90f
13: mv      a0, s3                          # a root
    mv      a1, s4
    li      a2, 32
    addi    a3, s1, ApiRoute_id_root
    call    route_hex
    bnez    a0, 98f
    li      t0, API_ID_ROOT
    sd      t0, ApiRoute_id_kind(s1)
    j       90f
14: addi    s5, s1, ApiRoute_validator      # validator_id, an id: an index or a public key
15: sd      zero, 0(s5)
    sd      zero, 8(s5)
    sd      zero, 16(s5)
    sd      zero, 24(s5)
    sd      zero, 32(s5)
    sd      zero, 40(s5)
    sd      zero, 48(s5)
    sd      zero, 56(s5)
    mv      a0, s3
    mv      a1, s4
    call    route_number
    bnez    a0, 151f
    li      t0, API_VALIDATOR_INDEX
    sd      t0, 0(s5)
    sd      a1, 8(s5)
    j       90f
151: mv     a0, s3
    mv      a1, s4
    li      a2, 48
    addi    a3, s5, ValidatorRef_pubkey
    call    route_hex
    bnez    a0, 98f
    li      t0, API_VALIDATOR_PUBKEY
    sd      t0, 0(s5)
    j       90f
16: beqz    s4, 98f                         # peer_id: 1 to 128 bytes of base58btc
    li      t0, 128
    bgtu    s4, t0, 98f
    lla     t1, route_base58
    li      t0, 0
161: bgeu   t0, s4, 90f
    add     t2, s3, t0
    lbu     t2, 0(t2)
    li      t3, 127
    bgtu    t2, t3, 98f
    srli    t3, t2, 6
    slli    t3, t3, 3
    add     t3, t1, t3
    ld      t3, 0(t3)
    srl     t3, t3, t2
    andi    t3, t3, 1
    beqz    t3, 98f
    addi    t0, t0, 1
    j       161b
17: mv      a0, s3                          # syncing_status: 100 to 599
    mv      a1, s4
    call    route_number
    bnez    a0, 98f
    li      t0, 100
    bltu    a1, t0, 98f
    li      t0, 599
    bgtu    a1, t0, 98f
    add     t0, s1, s6
    sd      a1, 0(t0)
    j       90f
18: li      a2, 32                          # hex to its field: a root, the reveal, the graffiti
    j       26f
19: li      a2, 96
    j       26f
20: li      a2, 32
26: mv      a0, s3
    mv      a1, s4
    add     a3, s1, s6
    call    route_hex
    bnez    a0, 98f
    j       90f
21: bnez    s4, 98f                         # skip_randao_verification: empty
    j       90f
22: mv      a0, s2                          # broadcast_validation: a word
    mv      a1, s3
    mv      a2, s4
    call    route_word
    beqz    a0, 98f
    add     t0, s1, s6
    sd      a1, 0(t0)
    j       90f
23: mv      a0, s2                          # a set: the word's bits
    mv      a1, s3
    mv      a2, s4
    call    route_word
    beqz    a0, 98f
    add     t0, s1, s6
    ld      t1, 0(t0)
    or      t1, t1, a1
    sd      t1, 0(t0)
    j       90f
24: mv      a0, s3                          # indices: a number
    mv      a1, s4
    call    route_number
    bnez    a0, 98f
    sd      a1, 0(s5)
    j       90f
25: mv      a0, s3                          # versioned_hashes: a root
    mv      a1, s4
    li      a2, 32
    mv      a3, s5
    call    route_hex
    bnez    a0, 98f
90: li      a0, 0
    LEAVE 0
98: li      a0, 1
    LEAVE 0
END_FUNCTION route_value

/*
 * L0: the weight, 0 to 1000, that the Accept value of a1 bytes at a0 gives the media type of a3
 * lower case bytes at a2 (lantern_api_route's rules). s1 bytes, s2 length, s3 media, s4 its length,
 * s5 the best kind of range (-1 none, 0 any type, 1 any application type, 2 the type), s6 its
 * weight, s7 an item's start, s8 its end, s9 a parameter's start, s10 a range's kind; L the item's
 * weight, L+8 the range's end or the next parameter's end.
 */
LOCAL_FUNCTION route_weight
    ENTER 16
    mv      s1, a0
    mv      s2, a1
    mv      s3, a2
    mv      s4, a3
    li      s5, -1
    li      s6, 0
    li      s7, 0
1:  bgtu    s7, s2, 9f                      # each item, up to a ,
    mv      a0, s1
    mv      a1, s7
    mv      a2, s2
    li      a3, ','
    call    http_find
    mv      s8, a0
    mv      a0, s1                          # the range: up to the first ;
    mv      a1, s7
    mv      a2, s8
    li      a3, ';'
    call    http_find
    mv      s9, a0
    mv      a0, s1
    mv      a1, s7
    mv      a2, s9
    call    http_trim
    sd      a0, L(sp)
    sd      a1, (L + 8)(sp)
    sub     a1, a1, a0
    add     a0, s1, a0
    mv      a2, s3
    mv      a3, s4
    call    http_same
    li      s10, 2
    bnez    a0, 3f
    ld      t0, L(sp)
    ld      a1, (L + 8)(sp)
    sub     a1, a1, t0
    add     a0, s1, t0
    lla     a2, route_t_any_application
    li      a3, route_t_any_application_len
    call    http_same
    li      s10, 1
    bnez    a0, 3f
    ld      t0, L(sp)
    ld      a1, (L + 8)(sp)
    sub     a1, a1, t0
    add     a0, s1, t0
    lla     a2, route_t_any
    li      a3, route_t_any_len
    call    http_same
    li      s10, 0
    beqz    a0, 8f                          # a range of another type: skipped
3:  li      t0, 1000                        # the parameters: q= sets the weight
    sd      t0, L(sp)
4:  bgeu    s9, s8, 7f
    addi    s9, s9, 1
    mv      a0, s1
    mv      a1, s9
    mv      a2, s8
    li      a3, ';'
    call    http_find
    sd      a0, (L + 8)(sp)
    mv      a2, a0
    mv      a0, s1
    mv      a1, s9
    call    http_trim
    ld      s9, (L + 8)(sp)
    sub     t0, a1, a0                      # a0, a1: the parameter
    li      t1, 2
    bltu    t0, t1, 4b
    add     t1, s1, a0
    lbu     t2, 0(t1)
    ori     t2, t2, 0x20
    li      t3, 'q'
    bne     t2, t3, 4b
    lbu     t2, 1(t1)
    li      t3, '='
    bne     t2, t3, 4b
    addi    t1, t1, 2                       # the value: 0, 0.ddd or 1, 1.000
    addi    t0, t0, -2
    beqz    t0, 8f
    li      t3, 1
    beq     t0, t3, 5f
    li      t3, 5
    bgtu    t0, t3, 8f
    lbu     t2, 1(t1)
    li      t3, '.'
    bne     t2, t3, 8f
5:  lbu     t2, 0(t1)
    li      t3, '1'
    beq     t2, t3, 6f
    li      t3, '0'
    bne     t2, t3, 8f
    li      t4, 0                           # 0.ddd: the digits, then scaled to thousandths
    li      t5, 2
    li      t6, 10
51: bgeu    t5, t0, 52f
    add     t2, t1, t5
    lbu     t2, 0(t2)
    addi    t2, t2, -48
    bgeu    t2, t6, 8f
    mul     t4, t4, t6
    add     t4, t4, t2
    addi    t5, t5, 1
    j       51b
52: li      t2, 5
    bgeu    t5, t2, 53f
    mul     t4, t4, t6
    addi    t5, t5, 1
    j       52b
53: li      t2, 1
    bne     t0, t2, 54f
    li      t4, 0
54: sd      t4, L(sp)
    j       4b
6:  li      t5, 2                           # 1.000
61: bgeu    t5, t0, 62f
    add     t2, t1, t5
    lbu     t2, 0(t2)
    li      t3, '0'
    bne     t2, t3, 8f
    addi    t5, t5, 1
    j       61b
62: li      t4, 1000
    sd      t4, L(sp)
    j       4b
7:  ld      t0, L(sp)                       # the most specific range, then the heaviest
    bgt     s10, s5, 71f
    blt     s10, s5, 8f
    bleu    t0, s6, 8f
71: mv      s5, s10
    mv      s6, t0
8:  addi    s7, s8, 1
    j       1b
9:  li      a0, 0
    bltz    s5, 91f
    mv      a0, s6
91: LEAVE 16
END_FUNCTION route_weight

/*
 * s1 the request, s2 out, s3 a path parameter's entry or a query item's start, s4 their count or
 * the item's end, s5 the operation's entry of api_routes, s6 the query, s7 its length, s8 present,
 * s9 the list's items, s10 the parameter at hand. Locals: L the path parameters (a count, then
 * API_PARAM_*, start, end for each, 2 at most), L+56 1 when the list has no room, L+64 the size of a
 * list item, L+72 and L+80 the peer id's start and end in the path, L+88 its length, L+96 the end of
 * an item's name, L+104 a value's cursor, L+112 1 when a comma ended an item, L+120 a count, L+128
 * an item (64 bytes), L+192 a decoded value (200 bytes).
 */
FUNCTION lantern_api_route
    ENTER 400
    ld      t0, 0(a1)
    li      t1, API_ROUTE_FIXED
    bltu    t0, t1, 97f
    mv      s1, a0
    mv      s2, a1
    addi    t0, s2, 8                       # every field after size 0
    li      t1, ((API_ROUTE_FIXED - 8) / 8)
1:  sd      zero, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, -1
    bnez    t1, 1b
    addi    t0, sp, L
    li      t1, 16
2:  sd      zero, 0(t0)
    addi    t0, t0, 8
    addi    t1, t1, -1
    bnez    t1, 2b
    li      s8, 0
    li      s9, 0
    li      s10, 0
    ld      t0, HttpRequest_path(s1)
    add     s3, s1, t0
    ld      s4, (HttpRequest_path + 8)(s1)
    ld      t0, HttpRequest_query(s1)
    add     s6, s1, t0
    ld      s7, (HttpRequest_query + 8)(s1)
    mv      a0, s3                          # the path: its percent-encoding, then its template
    mv      a1, s4
    call    route_pct_ok
    beqz    a0, 400f
    lla     s5, api_routes
    li      t0, API_OPS
    sd      t0, (L + 120)(sp)
3:  lla     a2, api_route_text
    ld      t0, 0(s5)
    add     a2, a2, t0
    lhu     a3, 8(s5)
    mv      a0, s3
    mv      a1, s4
    addi    a4, sp, L
    call    route_match
    bnez    a0, 4f
    addi    s5, s5, 32
    ld      t0, (L + 120)(sp)
    addi    t0, t0, -1
    sd      t0, (L + 120)(sp)
    bnez    t0, 3b
    j       404f
4:  ld      t2, 0(s5)                       # allow: the methods of the template; the operation of the method
    ld      t3, HttpRequest_method(s1)
    lla     t0, api_routes
    li      t1, API_OPS
    li      t4, 0
    li      t5, 0
5:  ld      t6, 0(t0)
    bne     t6, t2, 6f
    lbu     t6, 10(t0)
    addi    a5, t6, -1
    li      a6, 1
    sll     a6, a6, a5
    or      t4, t4, a6
    bne     t6, t3, 6f
    bnez    t5, 6f
    mv      t5, t0
6:  addi    t0, t0, 32
    addi    t1, t1, -1
    bnez    t1, 5b
    sd      t4, ApiRoute_allow(s2)
    beqz    t5, 405f
    mv      s5, t5
    lla     t0, api_routes
    sub     t0, s5, t0
    srli    t0, t0, 5
    addi    t0, t0, 1
    sd      t0, ApiRoute_op(s2)
    mv      a0, s6                          # the query's percent-encoding
    mv      a1, s7
    call    route_pct_ok
    beqz    a0, 400f
    addi    s3, sp, (L + 8)                 # the path parameters
    ld      s4, L(sp)
7:  beqz    s4, 20f
    ld      s10, 0(s3)
    ld      t0, HttpRequest_path(s1)
    add     a0, s1, t0
    ld      t0, 8(s3)
    add     a0, a0, t0
    ld      a1, 16(s3)
    sub     a1, a1, t0
    addi    a2, sp, (L + 192)
    li      a3, 200
    call    route_decode
    li      t0, 200
    bgtu    a0, t0, 401f
    sd      a0, (L + 88)(sp)
    mv      a3, a0
    mv      a0, s2
    mv      a1, s10
    addi    a2, sp, (L + 192)
    addi    a4, sp, (L + 128)
    call    route_value
    bnez    a0, 401f
    li      t0, 1
    sll     t0, t0, s10
    or      s8, s8, t0
    li      t0, API_PARAM_PEER_ID           # the peer id: written once the room is known
    bne     s10, t0, 8f
    ld      t0, 8(s3)
    sd      t0, (L + 72)(sp)
    ld      t0, 16(s3)
    sd      t0, (L + 80)(sp)
    j       9f
8:  sd      zero, (L + 88)(sp)
9:  addi    s3, s3, 24
    addi    s4, s4, -1
    j       7b
20: li      s3, 0                           # each query item
21: bgeu    s3, s7, 40f
    mv      a0, s6
    mv      a1, s3
    mv      a2, s7
    li      a3, '&'
    call    http_find
    mv      s4, a0
    beq     s4, s3, 39f
    mv      a0, s6                          # the name, up to the first =
    mv      a1, s3
    mv      a2, s4
    li      a3, '='
    call    http_find
    sd      a0, (L + 96)(sp)
    sub     a1, a0, s3
    add     a0, s6, s3
    addi    a2, sp, (L + 192)
    li      a3, 32
    call    route_decode
    li      t0, 32
    bgtu    a0, t0, 39f
    ld      t0, 16(s5)                      # a parameter the operation takes, by name
    li      s10, 1
22: li      t1, API_PARAMS
    bgtu    s10, t1, 39f
    srl     t1, t0, s10
    andi    t1, t1, 1
    beqz    t1, 24f
    lla     t2, api_params
    slli    t3, s10, 5
    add     t2, t2, t3
    ld      t3, 8(t2)
    bne     t3, a0, 24f
    ld      t3, 0(t2)
    lla     t4, api_param_text
    add     t3, t4, t3
    addi    t4, sp, (L + 192)
    li      t5, 0
23: bgeu    t5, a0, 25f
    add     t6, t4, t5
    lbu     t6, 0(t6)
    add     a5, t3, t5
    lbu     a5, 0(a5)
    bne     t6, a5, 24f
    addi    t5, t5, 1
    j       23b
24: addi    s10, s10, 1
    j       22b
25: ld      t0, (L + 96)(sp)                # the value: after the =, or empty
    bgeu    t0, s4, 26f
    addi    t0, t0, 1
26: sd      t0, (L + 104)(sp)
    li      t1, 1
    sll     t1, t1, s10
    lla     t2, api_params
    slli    t3, s10, 5
    add     t2, t2, t3
    ld      t2, 16(t2)
    li      t3, API_KIND_SET
    bgeu    t2, t3, 30f
    and     t3, s8, t1                      # one value: given once
    bnez    t3, 401f
    or      s8, s8, t1
    add     a0, s6, t0
    sub     a1, s4, t0
    addi    a2, sp, (L + 192)
    li      a3, 200
    call    route_decode
    li      t0, 200
    bgtu    a0, t0, 401f
    mv      a3, a0
    mv      a0, s2
    mv      a1, s10
    addi    a2, sp, (L + 192)
    addi    a4, sp, (L + 128)
    call    route_value
    bnez    a0, 401f
    j       39f
30: or      s8, s8, t1                      # a list or a set: each item
    li      t0, 64
    li      t3, API_KIND_ID_LIST
    beq     t2, t3, 31f
    li      t0, 8
    li      t3, API_KIND_INDEX_LIST
    beq     t2, t3, 31f
    li      t0, 32
    li      t3, API_KIND_HASH_LIST
    beq     t2, t3, 31f
    li      t0, 0
31: sd      t0, (L + 64)(sp)
32: li      t0, API_PARAM_ID                # the 65th id
    bne     s10, t0, 33f
    ld      t0, 8(s5)
    li      t1, (API_FLAG_ID_MAX << 24)
    and     t0, t0, t1
    beqz    t0, 33f
    li      t0, 64
    beq     s9, t0, 414f
33: mv      a0, s6
    ld      a1, (L + 104)(sp)
    mv      a2, s4
    addi    a3, sp, (L + 192)
    li      a4, 200
    call    route_next_item
    sd      a0, (L + 104)(sp)
    sd      a2, (L + 112)(sp)
    beqz    a1, 401f
    li      t0, 200
    bgtu    a1, t0, 401f
    mv      a3, a1
    mv      a0, s2
    mv      a1, s10
    addi    a2, sp, (L + 192)
    addi    a4, sp, (L + 128)
    call    route_value
    bnez    a0, 401f
    ld      t0, (L + 64)(sp)                # a list item: into out, while there is room
    beqz    t0, 36f
    addi    t1, s9, 1
    mul     t1, t1, t0
    addi    t1, t1, API_ROUTE_FIXED
    ld      t2, 0(s2)
    bleu    t1, t2, 34f
    li      t2, 1
    sd      t2, (L + 56)(sp)
    j       35f
34: sub     t1, t1, t0
    add     t1, s2, t1
    addi    t2, sp, (L + 128)
341: ld     t3, 0(t2)
    sd      t3, 0(t1)
    addi    t2, t2, 8
    addi    t1, t1, 8
    addi    t0, t0, -8
    bnez    t0, 341b
35: addi    s9, s9, 1
36: ld      t0, (L + 112)(sp)
    bnez    t0, 32b
39: addi    s3, s4, 1
    j       21b
40: ld      t0, 24(s5)                      # required parameters: the lowest missing
    not     t1, s8
    and     t0, t0, t1
    beqz    t0, 41f
    li      s10, 0
402: andi   t1, t0, 1
    bnez    t1, 401f
    srli    t0, t0, 1
    addi    s10, s10, 1
    j       402b
41: ld      t0, 8(s5)                       # Eth-Consensus-Version
    li      t1, (API_FLAG_VERSION << 24)
    and     t0, t0, t1
    beqz    t0, 42f
    li      s10, API_PARAM_CONSENSUS_VERSION
    li      a0, API_PARAM_CONSENSUS_VERSION
    ld      t0, HttpRequest_consensus_version(s1)
    add     a1, s1, t0
    ld      a2, (HttpRequest_consensus_version + 8)(s1)
    call    route_word
    beqz    a0, 401f
    sd      a1, ApiRoute_consensus_version(s2)
    li      t0, 1
    slli    t0, t0, API_PARAM_CONSENSUS_VERSION
    or      s8, s8, t0
42: ld      t0, HttpRequest_method(s1)      # Content-Type
    li      t1, HTTP_METHOD_POST
    bne     t0, t1, 44f
    li      t0, API_TYPE_JSON
    sd      t0, ApiRoute_body(s2)
    ld      t0, 8(s5)
    li      t1, (API_FLAG_SSZ_BODY << 24)
    and     t0, t0, t1
    beqz    t0, 44f
    ld      a2, (HttpRequest_content_type + 8)(s1)
    beqz    a2, 44f
    ld      t0, HttpRequest_content_type(s1)
    add     s3, s1, t0
    mv      a0, s3
    li      a1, 0
    li      a3, ';'
    call    http_find
    mv      a2, a0
    mv      a0, s3
    li      a1, 0
    call    http_trim
    add     s3, s3, a0
    sub     s4, a1, a0
    mv      a0, s3
    mv      a1, s4
    lla     a2, route_t_ssz
    li      a3, route_t_ssz_len
    call    http_same
    beqz    a0, 43f
    li      t0, API_TYPE_SSZ
    sd      t0, ApiRoute_body(s2)
    j       44f
43: mv      a0, s3
    mv      a1, s4
    lla     a2, route_t_json
    li      a3, route_t_json_len
    call    http_same
    beqz    a0, 415f
44: li      t0, API_TYPE_JSON               # Accept
    sd      t0, ApiRoute_response(s2)
    ld      t0, 8(s5)
    li      t1, (API_FLAG_SSZ_RESPONSE << 24)
    and     t0, t0, t1
    beqz    t0, 46f
    ld      s4, (HttpRequest_accept + 8)(s1)
    beqz    s4, 46f
    ld      t0, HttpRequest_accept(s1)
    add     s3, s1, t0
    mv      a0, s3
    mv      a1, s4
    lla     a2, route_t_json
    li      a3, route_t_json_len
    call    route_weight
    mv      s10, a0
    mv      a0, s3
    mv      a1, s4
    lla     a2, route_t_ssz
    li      a3, route_t_ssz_len
    call    route_weight
    or      t0, a0, s10
    beqz    t0, 406f
    bleu    a0, s10, 46f
    li      t0, API_TYPE_SSZ
    sd      t0, ApiRoute_response(s2)
46: ld      t0, (L + 56)(sp)                # the room: the list, then the peer id
    bnez    t0, 97f
    ld      t0, (L + 64)(sp)
    mul     s3, s9, t0
    ld      s4, (L + 88)(sp)
    addi    t0, s4, 7
    andi    t0, t0, -8
    add     t0, t0, s3
    addi    t0, t0, API_ROUTE_FIXED
    ld      t1, 0(s2)
    bgtu    t0, t1, 97f
    beqz    s9, 47f
    li      t0, API_ROUTE_FIXED
    sd      t0, ApiRoute_list(s2)
    sd      s9, (ApiRoute_list + 8)(s2)
47: beqz    s4, 48f
    addi    s3, s3, API_ROUTE_FIXED
    sd      s3, ApiRoute_peer_id(s2)
    sd      s4, (ApiRoute_peer_id + 8)(s2)
    ld      t0, HttpRequest_path(s1)
    add     a0, s1, t0
    ld      t0, (L + 72)(sp)
    add     a0, a0, t0
    ld      a1, (L + 80)(sp)
    sub     a1, a1, t0
    add     a2, s2, s3
    mv      a3, s4
    call    route_decode
    add     t0, s3, s4                      # zero bytes up to a multiple of 8
471: andi   t1, t0, 7
    beqz    t1, 48f
    add     t1, s2, t0
    sb      zero, 0(t1)
    addi    t0, t0, 1
    j       471b
48: ld      t0, 16(s5)                      # broadcast_validation: 1 when it is missing
    srli    t0, t0, API_PARAM_BROADCAST_VALIDATION
    andi    t0, t0, 1
    beqz    t0, 49f
    srli    t0, s8, API_PARAM_BROADCAST_VALIDATION
    andi    t0, t0, 1
    bnez    t0, 49f
    li      t0, 1
    sd      t0, ApiRoute_broadcast_validation(s2)
49: sd      s8, ApiRoute_present(s2)
    li      a0, LANTERN_OK
    LEAVE 400
400: li     s10, 0
401: li     t0, 400
    j       96f
404: li     t0, 404
    li      s10, 0
    j       96f
405: li     t0, 405
    li      s10, 0
    j       96f
406: li     t0, 406
    li      s10, 0
    j       96f
414: li     t0, 414
    j       96f
415: li     t0, 415
    li      s10, 0
96: sd      t0, ApiRoute_status(s2)
    sd      s10, ApiRoute_fault(s2)
    li      a0, LANTERN_INVALID_ROUTE
    LEAVE 400
97: li      a0, LANTERN_BUFFER_TOO_SMALL
    LEAVE 400
END_FUNCTION lantern_api_route
