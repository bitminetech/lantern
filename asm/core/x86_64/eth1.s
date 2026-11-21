/*
 * The eth1 follower's functions, x86-64: in the common object. Requirements: docs/reference/eth1.md.
 *
 * The parsers use the JSON helpers of jsonrpc.s, which read the end of the text from rbx; the
 * cursor is in rdi.
 */

    RODATA
.include "eth1_text.inc"
e1_digits:
    .ascii  "0123456789abcdef"

/* The QUANTITY of rax to the cursor rdi: "0x", then hex digits with no leading zero; rdi = the end. Uses rcx, rdx, r8. */
LOCAL_FUNCTION e1_qty
    UNWIND_END_PROLOGUE
    movw    $0x7830, (%rdi)                 # "0x"
    add     $2, %rdi
    mov     $60, %ecx                       # the highest nibble that is not zero, or the last
1:  test    %ecx, %ecx
    jz      2f
    mov     %rax, %rdx
    shr     %cl, %rdx
    and     $15, %edx
    jnz     2f
    sub     $4, %ecx
    jmp     1b
2:  lea     e1_digits(%rip), %r8
3:  mov     %rax, %rdx
    shr     %cl, %rdx
    and     $15, %edx
    movzbl  (%r8,%rdx), %edx
    mov     %dl, (%rdi)
    inc     %rdi
    test    %ecx, %ecx
    jz      4f
    sub     $4, %ecx
    jmp     3b
4:  ret
END_FUNCTION e1_qty

/* The rdx bytes at rsi as lowercase hex to the cursor rdi; rdi = the end. Uses rax, rcx, r8. */
LOCAL_FUNCTION e1_hex
    UNWIND_END_PROLOGUE
    lea     e1_digits(%rip), %r8
1:  test    %rdx, %rdx
    jz      2f
    movzbl  (%rsi), %eax
    inc     %rsi
    mov     %eax, %ecx
    shr     $4, %ecx
    movzbl  (%r8,%rcx), %ecx
    mov     %cl, (%rdi)
    and     $15, %eax
    movzbl  (%r8,%rax), %eax
    mov     %al, 1(%rdi)
    add     $2, %rdi
    dec     %rdx
    jmp     1b
2:  ret
END_FUNCTION e1_hex

/* (number, id, out): eth_getBlockByNumber. r12 number, r13 id, r14 out. */
FUNCTION lantern_eth_get_block_by_number
    ENTER 0
    mov     (%rdi), %r12
    mov     (%rsi), %r13
    mov     %rdx, %r14
    cmpq    $(24 + 128), (%r14)
    jb      8f
    lea     24(%r14), %rdi
    lea     e1_open(%rip), %rsi
    mov     $e1_open_len, %ecx
    rep movsb
    mov     %r13, %rax
    call    decimal
    lea     e1_block(%rip), %rsi
    mov     $e1_block_len, %ecx
    rep movsb
    cmp     $-1, %r12                       # 2^64 - 1: latest
    jne     1f
    lea     e1_latest(%rip), %rsi
    mov     $e1_latest_len, %ecx
    rep movsb
    jmp     2f
1:  mov     %r12, %rax
    call    e1_qty
2:  lea     e1_bclose(%rip), %rsi
    mov     $e1_bclose_len, %ecx
    rep movsb
    lea     24(%r14), %rax
    sub     %rax, %rdi
    movq    $24, 8(%r14)
    mov     %rdi, 16(%r14)
    xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION lantern_eth_get_block_by_number

/* (address, from, to, id, out): eth_getLogs of the DepositEvent logs. r12 address, r13 out, S7 from, S8 to, S9 id. */
FUNCTION lantern_eth_get_deposit_logs
    ENTER 0
    mov     %rdi, %r12
    mov     (%rsi), %rax
    mov     %rax, S7(%rsp)
    mov     (%rdx), %rax
    mov     %rax, S8(%rsp)
    mov     (%rcx), %rax
    mov     %rax, S9(%rsp)
    mov     %r8, %r13
    cmpq    $(24 + 384), (%r13)
    jb      8f
    lea     24(%r13), %rdi
    lea     e1_open(%rip), %rsi
    mov     $e1_open_len, %ecx
    rep movsb
    mov     S9(%rsp), %rax
    call    decimal
    lea     e1_logs(%rip), %rsi
    mov     $e1_logs_len, %ecx
    rep movsb
    mov     %r12, %rsi
    mov     $20, %edx
    call    e1_hex
    lea     e1_topics(%rip), %rsi
    mov     $e1_topics_len, %ecx
    rep movsb
    mov     S7(%rsp), %rax
    call    e1_qty
    lea     e1_to(%rip), %rsi
    mov     $e1_to_len, %ecx
    rep movsb
    mov     S8(%rsp), %rax
    call    e1_qty
    lea     e1_lclose(%rip), %rsi
    mov     $e1_lclose_len, %ecx
    rep movsb
    lea     24(%r13), %rax
    sub     %rax, %rdi
    movq    $24, 8(%r13)
    mov     %rdi, 16(%r13)
    xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION lantern_eth_get_deposit_logs

/*
 * A QUANTITY string at the cursor rdi: rdi = the cursor after it and rsi its value, or rdi = 0 for
 * none: "0x", then 1 to 16 hex digits with no leading zero. Uses rax, rcx, rdx, r8, r9.
 */
LOCAL_FUNCTION e1_qty_in
    UNWIND_END_PROLOGUE
    call    jstring
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx
    jnz     9f
    cmp     $3, %rdx
    jb      9f
    cmp     $18, %rdx
    ja      9f
    cmpw    $0x7830, (%rsi)                 # "0x"
    jne     9f
    add     $2, %rsi
    sub     $2, %rdx
    cmpb    $'0', (%rsi)                    # no leading zero, but 0x0
    jne     1f
    cmp     $1, %rdx
    jne     9f
1:  xor     %r8d, %r8d
2:  movzbl  (%rsi), %eax
    inc     %rsi
    lea     -'0'(%rax), %ecx
    cmp     $10, %ecx
    jb      3f
    or      $0x20, %eax
    lea     -'a'(%rax), %ecx
    cmp     $6, %ecx
    jae     9f
    add     $10, %ecx
3:  shl     $4, %r8
    or      %rcx, %r8
    dec     %rdx
    jnz     2b
    mov     %r8, %rsi
    ret
9:  xor     %edi, %edi
    ret
END_FUNCTION e1_qty_in

/*
 * (json, out): the number, hash and timestamp of an eth_getBlockByNumber result. rbx the text's
 * end, r12 out, r13 the members read: 1 number, 2 hash, 4 timestamp.
 */
FUNCTION lantern_eth1_block
    ENTER 0
    mov     %rsi, %r12
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, (%r12)
    movdqu  %xmm0, 16(%r12)
    movdqu  %xmm0, 32(%r12)
    movdqu  %xmm0, 48(%r12)
    movdqu  %xmm0, 64(%r12)
    movq    $0, 80(%r12)
    mov     8(%rdi), %rax
    mov     16(%rdi), %rcx
    add     %rax, %rdi
    lea     (%rdi,%rcx), %rbx
    xor     %r13d, %r13d
    call    jws
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $'{', (%rdi)
    jne     9f
    inc     %rdi
    mov     $1, %esi
1:  call    jmember
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx
    jnz     7f
    JIS     e1_n_number
    test    %eax, %eax
    jz      2f
    call    e1_qty_in
    test    %rdi, %rdi
    jz      9f
    mov     %rsi, Eth1Block_number(%r12)
    or      $1, %r13
    jmp     6f
2:  JIS     e1_n_timestamp
    test    %eax, %eax
    jz      3f
    call    e1_qty_in
    test    %rdi, %rdi
    jz      9f
    mov     %rsi, Eth1Block_timestamp(%r12)
    or      $4, %r13
    jmp     6f
3:  JIS     e1_n_hash
    test    %eax, %eax
    jz      4f
    xor     %esi, %esi
    mov     $32, %edx
    lea     Eth1Block_hash(%r12), %rcx
    call    jdata_in
    test    %rdi, %rdi
    jz      9f
    or      $2, %r13
    jmp     6f
4:  call    jskip
    test    %rdi, %rdi
    jz      9f
6:  xor     %esi, %esi
    jmp     1b
7:  call    jws                             # nothing after the object, and each of the three
    cmp     %rbx, %rdi
    jne     9f
    cmp     $7, %r13
    jne     9f
    xor     %eax, %eax
    LEAVE 0
9:  pxor    %xmm0, %xmm0
    movdqu  %xmm0, (%r12)
    movdqu  %xmm0, 16(%r12)
    movdqu  %xmm0, 32(%r12)
    movdqu  %xmm0, 48(%r12)
    mov     $LANTERN_INVALID_JSON, %eax
    LEAVE 0
END_FUNCTION lantern_eth1_block

/*
 * (json, out): the deposits of an eth_getLogs result. rbx the text's end, r12 out, r13 the next
 * entry, r14 the entries' end, r15 the members read (1 blockNumber, 2 topics, 4 data, 8 removed
 * true, 16 data of another length), S7 blockNumber, S8 a cursor, S9 where the data's bytes go, or
 * 0. Locals: L the topic (32), L+32 the data (576).
 */
FUNCTION lantern_eth1_deposit_logs
    ENTER 608
    mov     %rsi, %r12
    mov     8(%rdi), %rax
    mov     16(%rdi), %rcx
    add     %rax, %rdi
    lea     (%rdi,%rcx), %rbx
    mov     (%r12), %r14
    add     %r12, %r14
    lea     24(%r12), %r13
    movq    $24, 8(%r12)
    movq    $0, 16(%r12)
    call    jws
    cmp     %rbx, %rdi
    jae     90f
    cmpb    $'[', (%rdi)
    jne     90f
    inc     %rdi
    call    jws
    cmp     %rbx, %rdi
    jae     90f
    cmpb    $']', (%rdi)
    jne     1f
    inc     %rdi
    jmp     80f
1:  cmp     %rbx, %rdi                      # a log
    jae     90f
    cmpb    $'{', (%rdi)
    jne     90f
    inc     %rdi
    xor     %r15d, %r15d
    mov     $1, %esi
2:  call    jmember
    test    %rdi, %rdi
    jz      90f
    test    %rcx, %rcx
    jnz     40f
    JIS     e1_n_block_number
    test    %eax, %eax
    jz      3f
    call    e1_qty_in
    test    %rdi, %rdi
    jz      90f
    mov     %rsi, S7(%rsp)
    or      $1, %r15
    jmp     30f
3:  JIS     e1_n_removed
    test    %eax, %eax
    jz      4f
    and     $~8, %r15
    mov     %rdi, S8(%rsp)
    lea     json_false(%rip), %rsi
    mov     $json_false_len, %edx
    call    jliteral
    test    %rdi, %rdi
    jnz     30f
    mov     S8(%rsp), %rdi
    lea     json_true(%rip), %rsi
    mov     $json_true_len, %edx
    call    jliteral
    test    %rdi, %rdi
    jz      90f
    or      $8, %r15
    jmp     30f
4:  JIS     e1_n_topics
    test    %eax, %eax
    jz      5f
    cmp     %rbx, %rdi                      # an array: its first item the DepositEvent topic
    jae     90f
    cmpb    $'[', (%rdi)
    jne     90f
    inc     %rdi
    call    jws
    xor     %esi, %esi
    mov     $32, %edx
    lea     L(%rsp), %rcx
    call    jdata_in
    test    %rdi, %rdi
    jz      90f
    lea     L(%rsp), %rax
    lea     e1_topic(%rip), %rcx
    NE32    %rax, %rcx, 90f
41: call    jws
    cmp     %rbx, %rdi
    jae     90f
    movzbl  (%rdi), %eax
    inc     %rdi
    cmp     $']', %eax
    je      42f
    cmp     $',', %eax
    jne     90f
    call    jws
    call    jskip
    test    %rdi, %rdi
    jz      90f
    jmp     41b
42: or      $2, %r15
    jmp     30f
5:  JIS     e1_n_data
    test    %eax, %eax
    jz      6f
    call    jstring                         # "0x", then 2 hex digits a byte; 576 bytes, else no deposit's
    test    %rdi, %rdi
    jz      90f
    test    %rcx, %rcx
    jnz     90f
    cmp     $2, %rdx
    jb      90f
    test    $1, %rdx
    jnz     90f
    cmpw    $0x7830, (%rsi)
    jne     90f
    and     $~16, %r15
    add     $2, %rsi
    sub     $2, %rdx
    lea     (L + 32)(%rsp), %rax
    mov     %rax, S9(%rsp)
    cmp     $1152, %rdx
    je      52f
    or      $16, %r15
    movq    $0, S9(%rsp)                    # only the digits checked
52: test    %rdx, %rdx
    jz      55f
    xor     %r8d, %r8d
    mov     $2, %r9d
53: movzbl  (%rsi), %eax
    inc     %rsi
    lea     -'0'(%rax), %ecx
    cmp     $10, %ecx
    jb      54f
    or      $0x20, %eax
    lea     -'a'(%rax), %ecx
    cmp     $6, %ecx
    jae     90f
    add     $10, %ecx
54: shl     $4, %r8
    or      %rcx, %r8
    dec     %rdx
    dec     %r9d
    jnz     53b
    mov     S9(%rsp), %rax
    test    %rax, %rax
    jz      52b
    mov     %r8b, (%rax)
    incq    S9(%rsp)
    jmp     52b
55: or      $4, %r15
    jmp     30f
6:  call    jskip
    test    %rdi, %rdi
    jz      90f
30: xor     %esi, %esi
    jmp     2b
40: mov     %r15, %rax                      # the log's end: blockNumber, topics and data
    and     $7, %eax
    cmp     $7, %eax
    jne     90f
    test    $8, %r15                        # removed: no deposit
    jnz     70f
    test    $16, %r15
    jnz     91f
    mov     %rdi, S8(%rsp)
    lea     (L + 32)(%rsp), %rdi            # the contract's encoding: the bytes of e1_abi but the values
    call    e1_abi_check
    test    %eax, %eax
    jz      91f
    lea     Eth1Deposit__mem(%r13), %rax
    cmp     %r14, %rax
    ja      92f
    mov     S7(%rsp), %rax
    mov     %rax, Eth1Deposit_block_number(%r13)
    mov     (L + 32 + 544)(%rsp), %rax      # index
    mov     %rax, Eth1Deposit_index(%r13)
    lea     Eth1Deposit_data(%r13), %rdi    # pubkey
    lea     (L + 32 + 192)(%rsp), %rsi
    mov     $48, %ecx
    rep movsb
    lea     (L + 32 + 288)(%rsp), %rsi      # withdrawal_credentials
    mov     $32, %ecx
    rep movsb
    mov     (L + 32 + 352)(%rsp), %rax      # amount
    mov     %rax, (%rdi)
    add     $8, %rdi
    lea     (L + 32 + 416)(%rsp), %rsi      # signature
    mov     $96, %ecx
    rep movsb
    add     $Eth1Deposit__mem, %r13
    mov     S8(%rsp), %rdi
70: call    jws                             # a comma and the next log, or the array's end
    cmp     %rbx, %rdi
    jae     90f
    movzbl  (%rdi), %eax
    inc     %rdi
    cmp     $',', %eax
    jne     71f
    call    jws
    jmp     1b
71: cmp     $']', %eax
    jne     90f
80: call    jws                             # nothing after the array
    cmp     %rbx, %rdi
    jne     90f
    lea     24(%r12), %rax
    mov     %r13, %rcx
    sub     %rax, %rcx
    mov     %rcx, 16(%r12)
    xor     %eax, %eax
    LEAVE 608
90: mov     $LANTERN_INVALID_JSON, %eax
    LEAVE 608
91: mov     $LANTERN_INVALID_DEPOSIT_LOG, %eax
    LEAVE 608
92: mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 608
END_FUNCTION lantern_eth1_deposit_logs

/*
 * eax = 1 when the 576 bytes at rdi are e1_abi but in the values (pubkey 192, withdrawal
 * credentials 288, amount 352, signature 416, index 544), else 0. Uses rcx, rdx, r8.
 */
LOCAL_FUNCTION e1_abi_check
    UNWIND_END_PROLOGUE
    lea     e1_abi(%rip), %r8
    xor     %ecx, %ecx
1:  cmp     $576, %ecx
    jae     8f
    cmp     $192, %ecx                      # the value ranges are skipped
    jb      3f
    cmp     $240, %ecx
    jb      2f
    cmp     $288, %ecx
    jb      3f
    cmp     $320, %ecx
    jb      2f
    cmp     $352, %ecx
    jb      3f
    cmp     $360, %ecx
    jb      2f
    cmp     $416, %ecx
    jb      3f
    cmp     $512, %ecx
    jb      2f
    cmp     $544, %ecx
    jb      3f
    cmp     $552, %ecx
    jb      2f
3:  movzbl  (%rdi,%rcx), %edx
    cmp     (%r8,%rcx), %dl
    jne     9f
2:  inc     %ecx
    jmp     1b
8:  mov     $1, %eax
    ret
9:  xor     %eax, %eax
    ret
END_FUNCTION e1_abi_check

/* SHA-256 of the 32 bytes at rdi and the 32 bytes at rsi, to rdx. Locals: out, then a ByteList of 64 bytes. */
LOCAL_FUNCTION e1_hash2
    FRAME 96
    mov     %rdx, (%rsp)
    movq    $88, 8(%rsp)
    movq    $24, 16(%rsp)
    movq    $64, 24(%rsp)
    lea     32(%rsp), %rax
    COPY32  %rax, %rdi
    lea     64(%rsp), %rax
    COPY32  %rax, %rsi
    lea     8(%rsp), %rdi
    mov     (%rsp), %rsi
    CALL_GLOBAL crypto_sha256
    UNFRAME 96
END_FUNCTION e1_hash2

/*
 * (data, out): hash_tree_root of a DepositData. r12 data, r13 out. Locals: L the pubkey's last
 * chunk, L+32 the pubkey's root, then the first half's, L+64 the signature's halves and root, then
 * the second half's, L+96 a chunk, L+128 a zero chunk.
 */
FUNCTION lantern_deposit_leaf
    ENTER 160
    mov     %rdi, %r12
    mov     %rsi, %r13
    pxor    %xmm0, %xmm0                    # pubkey: its two chunks
    movdqu  32(%r12), %xmm1
    movdqu  %xmm1, L(%rsp)
    movdqu  %xmm0, (L + 16)(%rsp)
    mov     %r12, %rdi
    lea     L(%rsp), %rsi
    lea     (L + 32)(%rsp), %rdx
    call    e1_hash2
    lea     (L + 32)(%rsp), %rdi            # with withdrawal_credentials
    lea     48(%r12), %rsi
    lea     (L + 32)(%rsp), %rdx
    call    e1_hash2
    lea     88(%r12), %rdi                  # signature: its four chunks, the last zero
    lea     120(%r12), %rsi
    lea     (L + 64)(%rsp), %rdx
    call    e1_hash2
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, (L + 128)(%rsp)
    movdqu  %xmm0, (L + 144)(%rsp)
    lea     152(%r12), %rdi
    lea     (L + 128)(%rsp), %rsi
    lea     (L + 96)(%rsp), %rdx
    call    e1_hash2
    lea     (L + 64)(%rsp), %rdi
    lea     (L + 96)(%rsp), %rsi
    lea     (L + 64)(%rsp), %rdx
    call    e1_hash2
    pxor    %xmm0, %xmm0                    # amount, then the signature
    movdqu  %xmm0, (L + 96)(%rsp)
    movdqu  %xmm0, (L + 112)(%rsp)
    mov     80(%r12), %rax
    mov     %rax, (L + 96)(%rsp)
    lea     (L + 96)(%rsp), %rdi
    lea     (L + 64)(%rsp), %rsi
    lea     (L + 64)(%rsp), %rdx
    call    e1_hash2
    lea     (L + 32)(%rsp), %rdi            # the two halves
    lea     (L + 64)(%rsp), %rsi
    mov     %r13, %rdx
    call    e1_hash2
    xor     %eax, %eax
    LEAVE 160
END_FUNCTION lantern_deposit_leaf

/* (tree, leaf): the deposit contract's deposit. r12 the tree, r13 the size, S7 the height. Locals: L the node (32). */
FUNCTION lantern_deposit_tree_push
    ENTER 32
    mov     %rdi, %r12
    mov     DepositTree_count(%r12), %rax
    mov     $0xffffffff, %ecx
    cmp     %rcx, %rax
    jae     8f
    inc     %rax
    mov     %rax, DepositTree_count(%r12)
    mov     %rax, %r13
    lea     L(%rsp), %rdi
    COPY32  %rdi, %rsi
    movq    $0, S7(%rsp)
1:  mov     S7(%rsp), %rcx
    shl     $5, %rcx
    lea     DepositTree_branch(%r12,%rcx), %rdi
    test    $1, %r13
    jz      2f
    lea     L(%rsp), %rsi                   # an odd size: the node is the branch at this height
    COPY32  %rdi, %rsi
    jmp     7f
2:  lea     L(%rsp), %rsi
    lea     L(%rsp), %rdx
    call    e1_hash2
    shr     %r13
    incq    S7(%rsp)
    cmpq    $DEPOSIT_CONTRACT_TREE_DEPTH, S7(%rsp)
    jb      1b
7:  xor     %eax, %eax
    LEAVE 32
8:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    LEAVE 32
END_FUNCTION lantern_deposit_tree_push

/*
 * (tree, out): get_deposit_root. r12 the tree, r13 out, S7 the size, S8 the height. Locals: L the
 * node (32), L+32 the zero hash of the height (32), L+64 the count's 32 bytes.
 */
FUNCTION lantern_deposit_tree_root
    ENTER 96
    mov     %rdi, %r12
    mov     %rsi, %r13
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, L(%rsp)
    movdqu  %xmm0, (L + 16)(%rsp)
    movdqu  %xmm0, (L + 32)(%rsp)
    movdqu  %xmm0, (L + 48)(%rsp)
    mov     DepositTree_count(%r12), %rax
    mov     %rax, S7(%rsp)
    movq    $0, S8(%rsp)
1:  mov     S8(%rsp), %rcx
    shl     $5, %rcx
    lea     DepositTree_branch(%r12,%rcx), %rdi
    lea     L(%rsp), %rsi
    testq   $1, S7(%rsp)
    jnz     2f
    lea     L(%rsp), %rdi                   # an even size: the node, then the zero hash
    lea     (L + 32)(%rsp), %rsi
2:  lea     L(%rsp), %rdx
    call    e1_hash2
    lea     (L + 32)(%rsp), %rdi            # the zero hash of the next height
    mov     %rdi, %rsi
    mov     %rdi, %rdx
    call    e1_hash2
    shrq    S7(%rsp)
    incq    S8(%rsp)
    cmpq    $DEPOSIT_CONTRACT_TREE_DEPTH, S8(%rsp)
    jb      1b
    mov     DepositTree_count(%r12), %rax   # the count, little endian, and 24 zero bytes
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, (L + 64)(%rsp)
    movdqu  %xmm0, (L + 80)(%rsp)
    mov     %rax, (L + 64)(%rsp)
    lea     L(%rsp), %rdi
    lea     (L + 64)(%rsp), %rsi
    mov     %r13, %rdx
    call    e1_hash2
    xor     %eax, %eax
    LEAVE 96
END_FUNCTION lantern_deposit_tree_root

/*
 * (leaves, count, index, scratch, out): the proof of the leaf at index in the tree of the first
 * count leaves. r12 the level's nodes, r13 its count, S7 the index at the level, S8 out, S9 the
 * height, S10 scratch's nodes. Locals: L the zero hash of the height (32), L+32 a node (32), L+64
 * the count, L+72 the next level's index.
 */
FUNCTION lantern_deposit_proof
    ENTER 80
    mov     (%rsi), %rax
    mov     %rax, (L + 64)(%rsp)
    mov     (%rdx), %r9
    mov     %r9, S7(%rsp)
    mov     %r8, S8(%rsp)
    cmp     %rax, %r9
    jae     7f
    mov     16(%rdi), %r10
    shr     $5, %r10
    cmp     %r10, %rax
    ja      7f
    mov     8(%rdi), %r10
    lea     (%rdi,%r10), %r12
    mov     %rax, %r10                      # the next level's nodes from scratch's byte 8
    shl     $4, %r10
    add     $(8 + 32), %r10
    cmp     %r10, (%rcx)
    jb      8f
    lea     8(%rcx), %r10
    mov     %r10, S10(%rsp)
    mov     %rax, %r13
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, L(%rsp)
    movdqu  %xmm0, (L + 16)(%rsp)
    movq    $0, S9(%rsp)
1:  mov     S7(%rsp), %rcx                  # the sibling, or the zero hash past the level's count
    xor     $1, %rcx
    mov     S9(%rsp), %rdi
    shl     $5, %rdi
    add     S8(%rsp), %rdi
    lea     L(%rsp), %rsi
    cmp     %r13, %rcx
    jae     2f
    shl     $5, %rcx
    lea     (%r12,%rcx), %rsi
2:  COPY32  %rdi, %rsi
    movq    $0, (L + 72)(%rsp)              # the next level, in scratch
3:  mov     (L + 72)(%rsp), %rcx
    shl     $1, %rcx
    cmp     %r13, %rcx
    jae     5f
    mov     %rcx, %rdi
    shl     $5, %rdi
    add     %r12, %rdi
    inc     %rcx
    lea     L(%rsp), %rsi
    cmp     %r13, %rcx
    jae     4f
    shl     $5, %rcx
    lea     (%r12,%rcx), %rsi
4:  lea     (L + 32)(%rsp), %rdx
    call    e1_hash2
    mov     (L + 72)(%rsp), %rdi
    shl     $5, %rdi
    add     S10(%rsp), %rdi
    lea     (L + 32)(%rsp), %rsi
    COPY32  %rdi, %rsi
    incq    (L + 72)(%rsp)
    jmp     3b
5:  mov     S10(%rsp), %r12
    mov     (L + 72)(%rsp), %r13
    shrq    S7(%rsp)
    lea     L(%rsp), %rdi                   # the zero hash of the next height
    mov     %rdi, %rsi
    mov     %rdi, %rdx
    call    e1_hash2
    incq    S9(%rsp)
    cmpq    $DEPOSIT_CONTRACT_TREE_DEPTH, S9(%rsp)
    jb      1b
    mov     S8(%rsp), %rdi                  # then the count as 32 little endian bytes
    add     $(32 * DEPOSIT_CONTRACT_TREE_DEPTH), %rdi
    pxor    %xmm0, %xmm0
    movdqu  %xmm0, (%rdi)
    movdqu  %xmm0, 16(%rdi)
    mov     (L + 64)(%rsp), %rax
    mov     %rax, (%rdi)
    xor     %eax, %eax
    LEAVE 80
7:  mov     $LANTERN_INVALID_INDEX, %eax
    LEAVE 80
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 80
END_FUNCTION lantern_deposit_proof
