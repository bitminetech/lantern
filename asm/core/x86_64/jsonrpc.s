/*
 * The JSON-RPC response parser of the Engine API client, x86-64: in the common object.
 * Requirements: docs/reference/engine-api.md.
 *
 * The local functions read the end of the body from rbx, the EngineResponse from rbp and the
 * method from r12, which lantern_engine_parse_response sets. The cursor is in rdi; a cursor
 * of 0 means the JSON is not valid.
 */

/* The names and strings the parser reads, before the code that takes their lengths. */
    RODATA
.include "jsonrpc_names.inc"

/* L0: rdi = the cursor rdi after any whitespace. Uses eax. */
LOCAL_FUNCTION jws
    UNWIND_END_PROLOGUE
1:  cmp     %rbx, %rdi
    jae     2f
    movzbl  (%rdi), %eax
    cmp     $' ', %eax
    je      3f
    cmp     $9, %eax
    je      3f
    cmp     $10, %eax
    je      3f
    cmp     $13, %eax
    jne     2f
3:  inc     %rdi
    jmp     1b
2:  ret
END_FUNCTION jws

/*
 * L0: a string at the cursor rdi, its quote included: rdi = the cursor after it, rsi = where its
 * bytes start, rdx = their count, rcx = 1 when it has an escape. Uses rax, r8, r9.
 */
LOCAL_FUNCTION jstring
    UNWIND_END_PROLOGUE
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $'"', (%rdi)
    jne     9f
    inc     %rdi
    mov     %rdi, %rsi
    xor     %ecx, %ecx
1:  cmp     %rbx, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    inc     %rdi
    cmp     $'"', %eax
    je      8f
    cmp     $0x20, %eax                     # no control character
    jb      9f
    cmp     $'\\', %eax
    jne     1b
    mov     $1, %ecx                        # an escape
    cmp     %rbx, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    inc     %rdi
    cmp     $'u', %eax
    je      2f
    lea     json_escapes(%rip), %r8
    xor     %r9d, %r9d
3:  cmp     (%r8,%r9), %al
    je      1b
    inc     %r9
    cmp     $8, %r9
    jb      3b
    jmp     9f
2:  mov     $4, %r9d                        # \uXXXX
4:  cmp     %rbx, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    inc     %rdi
    lea     -'0'(%rax), %r8d
    cmp     $10, %r8d
    jb      5f
    or      $0x20, %eax
    sub     $'a', %eax
    cmp     $6, %eax
    jae     9f
5:  dec     %r9
    jnz     4b
    jmp     1b
8:  mov     %rdi, %rdx
    sub     %rsi, %rdx
    dec     %rdx
    ret
9:  xor     %edi, %edi
    ret
END_FUNCTION jstring

/* L0: a number at the cursor rdi, as RFC 8259 writes it: rdi = the cursor after it, rsi = 1 when it is digits only. Uses rax, r8. */
LOCAL_FUNCTION jnumber
    UNWIND_END_PROLOGUE
    mov     $1, %esi
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $'-', (%rdi)
    jne     1f
    inc     %rdi
1:  cmp     %rbx, %rdi                      # 0, or a digit 1 to 9 and digits
    jae     9f
    movzbl  (%rdi), %eax
    inc     %rdi
    cmp     $'0', %eax
    je      3f
    sub     $'1', %eax
    cmp     $9, %eax
    jae     9f
2:  cmp     %rbx, %rdi
    jae     7f
    movzbl  (%rdi), %eax
    sub     $'0', %eax
    cmp     $10, %eax
    jae     3f
    inc     %rdi
    jmp     2b
3:  cmp     %rbx, %rdi                      # a fraction
    jae     7f
    cmpb    $'.', (%rdi)
    jne     5f
    xor     %esi, %esi
    inc     %rdi
    xor     %r8d, %r8d
4:  cmp     %rbx, %rdi
    jae     6f
    movzbl  (%rdi), %eax
    sub     $'0', %eax
    cmp     $10, %eax
    jae     6f
    inc     %rdi
    inc     %r8
    jmp     4b
6:  test    %r8, %r8
    jz      9f
5:  cmp     %rbx, %rdi                      # an exponent
    jae     7f
    movzbl  (%rdi), %eax
    or      $0x20, %eax
    cmp     $'e', %eax
    jne     7f
    xor     %esi, %esi
    inc     %rdi
    cmp     %rbx, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    cmp     $'+', %eax
    je      10f
    cmp     $'-', %eax
    jne     11f
10: inc     %rdi
11: xor     %r8d, %r8d
12: cmp     %rbx, %rdi
    jae     13f
    movzbl  (%rdi), %eax
    sub     $'0', %eax
    cmp     $10, %eax
    jae     13f
    inc     %rdi
    inc     %r8
    jmp     12b
13: test    %r8, %r8
    jz      9f
7:  ret
9:  xor     %edi, %edi
    ret
END_FUNCTION jnumber

/* Whether the rdx bytes at rsi are the literal label: eax = 1 or 0. Uses r8, r9, r10. */
.macro JIS label
    xor     %eax, %eax
    cmp     $\label\()_len, %rdx
    jne     93f
    lea     \label(%rip), %r8
    xor     %r9d, %r9d
91: movzbl  (%rsi,%r9), %r10d
    cmp     (%r8,%r9), %r10b
    jne     93f
    inc     %r9
    cmp     %rdx, %r9
    jb      91b
    mov     $1, %eax
93:
.endm

/* L0: the literal at the cursor rdi of the rdx bytes at rsi: rdi = the cursor after it, or 0. Uses rax, r8. */
LOCAL_FUNCTION jliteral
    UNWIND_END_PROLOGUE
    mov     %rbx, %rax
    sub     %rdi, %rax
    cmp     %rdx, %rax
    jb      9f
    xor     %r8d, %r8d
1:  movzbl  (%rdi,%r8), %eax
    cmp     (%rsi,%r8), %al
    jne     9f
    inc     %r8
    cmp     %rdx, %r8
    jb      1b
    add     %rdx, %rdi
    ret
9:  xor     %edi, %edi
    ret
END_FUNCTION jliteral

/*
 * L0: any value at the cursor rdi, as RFC 8259 writes it: rdi = the cursor after it. Brackets nest
 * to 64 levels, their kinds in r13 (1 for an object), the depth in r14; r10 what comes next: 0 a
 * value, 1 a value or the array's end, 2 a name, 3 a name or the object's end. Uses rax, rcx, rdx,
 * rsi, r8, r9, r10.
 */
LOCAL_FUNCTION jskip
    push    %r13
    UNWIND_PUSH %r13
    push    %r14
    UNWIND_PUSH %r14
    UNWIND_END_PROLOGUE
    xor     %r13d, %r13d
    xor     %r14d, %r14d
    xor     %r10d, %r10d
1:  call    jws
    cmp     %rbx, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    cmp     $2, %r10
    jb      30f
    cmp     $'}', %eax                      # a name and a colon, or the end of an empty object
    jne     31f
    cmp     $3, %r10
    je      5f
    jmp     9f
31: cmp     $'"', %eax
    jne     9f
    call    jstring
    test    %rdi, %rdi
    jz      9f
    call    jws
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $':', (%rdi)
    jne     9f
    inc     %rdi
    xor     %r10d, %r10d
    jmp     1b
30: cmp     $']', %eax                      # a value, or the end of an empty array
    jne     32f
    cmp     $1, %r10
    je      5f
    jmp     9f
32: cmp     $'"', %eax
    jne     2f
    call    jstring
    test    %rdi, %rdi
    jz      9f
    jmp     6f
2:  cmp     $'{', %eax
    je      3f
    cmp     $'[', %eax
    jne     7f
3:  cmp     $64, %r14
    jae     9f
    shl     $1, %r13
    mov     $1, %r10d
    cmp     $'{', %eax
    jne     14f
    or      $1, %r13
    mov     $3, %r10d
14: inc     %r14
    inc     %rdi
    jmp     1b
5:  shr     $1, %r13                        # the end of the container
    dec     %r14
    inc     %rdi
6:  test    %r14, %r14                      # a whole value at depth 0
    jz      8f
    call    jws                             # in a container: a comma, or the end of its kind
    cmp     %rbx, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    mov     %r13, %rcx
    and     $1, %ecx
    cmp     $',', %eax
    jne     33f
    inc     %rdi
    lea     (%rcx,%rcx), %r10
    jmp     1b
33: mov     $']', %edx
    test    %ecx, %ecx
    jz      34f
    mov     $'}', %edx
34: cmp     %edx, %eax
    je      5b
    jmp     9f
7:  cmp     $'t', %eax                      # true, false, null, or a number
    jne     11f
    lea     json_true(%rip), %rsi
    mov     $4, %edx
    call    jliteral
    test    %rdi, %rdi
    jz      9f
    jmp     6b
11: cmp     $'f', %eax
    jne     12f
    lea     json_false(%rip), %rsi
    mov     $5, %edx
    call    jliteral
    test    %rdi, %rdi
    jz      9f
    jmp     6b
12: cmp     $'n', %eax
    jne     13f
    lea     json_null(%rip), %rsi
    mov     $4, %edx
    call    jliteral
    test    %rdi, %rdi
    jz      9f
    jmp     6b
13: call    jnumber
    test    %rdi, %rdi
    jz      9f
    jmp     6b
9:  xor     %edi, %edi
8:  UNWIND_BEGIN_EPILOGUE
    pop     %r14
    UNWIND_POP %r14
    pop     %r13
    UNWIND_POP %r13
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION jskip

/*
 * L0: the next member of an object, from the cursor rdi after its brace (rsi = 1) or after a
 * value (rsi = 0): rcx = 1 at the closing brace, rdi after it; else rdi = its value after
 * whitespace, rsi = where its name's bytes start, rdx = their count, 2^64 - 1 for a name with
 * an escape. rdi = 0 when the JSON is not valid. Uses rax, r8, r9, r11.
 */
LOCAL_FUNCTION jmember
    UNWIND_END_PROLOGUE
    mov     %rsi, %r11
    call    jws
    cmp     %rbx, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    cmp     $'}', %eax
    jne     1f
    inc     %rdi                            # the end: after the brace or a value, not after a comma
    mov     $1, %ecx
    ret
1:  test    %r11, %r11
    jnz     2f
    cmp     $',', %eax
    jne     9f
    inc     %rdi
    call    jws
2:  call    jstring
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx
    jz      3f
    mov     $-1, %rdx
3:  call    jws
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $':', (%rdi)
    jne     9f
    inc     %rdi
    call    jws
    xor     %ecx, %ecx
    ret
9:  xor     %edi, %edi
    ret
END_FUNCTION jmember

/*
 * L0: DATA of rdx bytes at the cursor rdi, or null when rsi = 1 allows it, to rcx:
 * rdi = the cursor after it, rsi = 1 when it is not null. Uses rax, rdx, r8-r11.
 */
LOCAL_FUNCTION jdata_in
    UNWIND_END_PROLOGUE
    mov     %rdx, %r10
    mov     %rcx, %r11
    test    %rsi, %rsi
    jz      1f
    cmp     %rbx, %rdi
    jae     1f
    cmpb    $'n', (%rdi)
    jne     1f
    lea     json_null(%rip), %rsi
    mov     $4, %edx
    call    jliteral
    xor     %esi, %esi
    ret
1:  call    jstring
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx                      # "0x", then 2 hex digits a byte
    jnz     9f
    lea     2(%r10,%r10), %rax
    cmp     %rax, %rdx
    jne     9f
    cmpb    $'0', (%rsi)
    jne     9f
    cmpb    $'x', 1(%rsi)
    jne     9f
    add     $2, %rsi
2:  test    %r10, %r10
    jz      5f
    xor     %edx, %edx
    mov     $2, %r9d
3:  movzbl  (%rsi), %eax
    inc     %rsi
    lea     -'0'(%rax), %r8d
    cmp     $10, %r8d
    jb      4f
    or      $0x20, %eax
    lea     -'a'(%rax), %r8d
    cmp     $6, %r8d
    jae     9f
    add     $10, %r8d
4:  shl     $4, %edx
    or      %r8d, %edx
    dec     %r9
    jnz     3b
    mov     %dl, (%r11)
    inc     %r11
    dec     %r10
    jmp     2b
5:  mov     $1, %esi
    ret
9:  xor     %edi, %edi
    ret
END_FUNCTION jdata_in

/*
 * L0: an entry of the table at r15 (a length byte and the bytes, then a 0 byte) that the rdx
 * bytes at rsi match: rax = its index, or 2^64 - 1. Uses r8, r9, r10, r11.
 */
LOCAL_FUNCTION jtable
    UNWIND_END_PROLOGUE
    mov     %r15, %r8
    xor     %eax, %eax
1:  movzbl  (%r8), %r9d
    inc     %r8
    test    %r9, %r9
    jz      4f
    cmp     %rdx, %r9
    jne     3f
    xor     %r10d, %r10d
2:  movzbl  (%rsi,%r10), %r11d
    cmp     (%r8,%r10), %r11b
    jne     3f
    inc     %r10
    cmp     %rdx, %r10
    jb      2b
    ret
3:  add     %r9, %r8
    inc     %rax
    jmp     1b
4:  mov     $-1, %rax
    ret
END_FUNCTION jtable

/* L0: a PayloadStatusV1 object at the cursor rdi, into rbp: rdi = the cursor after it. r13 1 when status is seen. */
LOCAL_FUNCTION jpayload_status
    ENTER 0
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $'{', (%rdi)
    jne     9f
    inc     %rdi
    xor     %r13d, %r13d
    mov     $1, %esi
1:  call    jmember
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx
    jnz     8f
    JIS     json_status
    test    %eax, %eax
    jz      3f
    call    jstring                         # status: one of the five
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx
    jnz     9f
    lea     json_statuses(%rip), %r15
    call    jtable
    cmp     $-1, %rax
    je      9f
    inc     %rax
    mov     %rax, EngineResponse_status(%rbp)
    mov     $1, %r13d
    jmp     7f
3:  JIS     json_latest_valid_hash
    test    %eax, %eax
    jz      6f
    mov     $1, %esi                        # latestValidHash: 32 bytes or null
    mov     $32, %edx
    lea     EngineResponse_latest_valid_hash(%rbp), %rcx
    call    jdata_in
    test    %rdi, %rdi
    jz      9f
    mov     %rsi, EngineResponse_has_latest_valid_hash(%rbp)
    jmp     7f
6:  call    jskip
    test    %rdi, %rdi
    jz      9f
7:  xor     %esi, %esi
    jmp     1b
8:  test    %r13, %r13
    jz      9f
    LEAVE 0
9:  xor     %edi, %edi
    LEAVE 0
END_FUNCTION jpayload_status

/* L0: the result of the method in r12 at the cursor rdi, r15 the body's first byte: rdi = the cursor after it. */
LOCAL_FUNCTION jresult
    ENTER 0
    cmp     $ENGINE_METHOD_NEW_PAYLOAD, %r12
    jne     1f
    call    jpayload_status
    LEAVE 0
1:  cmp     $ENGINE_METHOD_FORKCHOICE_UPDATED, %r12
    jne     5f
    cmp     %rbx, %rdi                      # {"payloadStatus": ..., "payloadId": ...}
    jae     9f
    cmpb    $'{', (%rdi)
    jne     9f
    inc     %rdi
    xor     %r14d, %r14d
    mov     $1, %esi
2:  call    jmember
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx
    jnz     4f
    JIS     json_payload_status
    test    %eax, %eax
    jz      3f
    call    jpayload_status
    test    %rdi, %rdi
    jz      9f
    mov     $1, %r14d
    xor     %esi, %esi
    jmp     2b
3:  JIS     json_payload_id
    test    %eax, %eax
    jz      6f
    mov     $1, %esi                        # payloadId: 8 bytes or null
    mov     $8, %edx
    lea     EngineResponse_payload_id(%rbp), %rcx
    call    jdata_in
    test    %rdi, %rdi
    jz      9f
    mov     %rsi, EngineResponse_has_payload_id(%rbp)
    xor     %esi, %esi
    jmp     2b
6:  call    jskip
    test    %rdi, %rdi
    jz      9f
    xor     %esi, %esi
    jmp     2b
4:  test    %r14, %r14
    jz      9f
    LEAVE 0
5:  cmp     $ENGINE_METHOD_GET_PAYLOAD, %r12
    jne     17f
    cmp     %rbx, %rdi                      # getPayload: an object, its bytes kept
    jae     9f
    cmpb    $'{', (%rdi)
    jne     9f
    mov     %rdi, %rax
    sub     %r15, %rax
    mov     %rax, EngineResponse_result_offset(%rbp)
    call    jskip
    test    %rdi, %rdi
    jz      9f
    mov     %rdi, %rax
    sub     %r15, %rax
    sub     EngineResponse_result_offset(%rbp), %rax
    mov     %rax, EngineResponse_result_length(%rbp)
    LEAVE 0
17: cmp     %rbx, %rdi                      # exchangeCapabilities: an array of strings
    jae     9f
    cmpb    $'[', (%rdi)
    jne     9f
    inc     %rdi
    call    jws
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $']', (%rdi)
    je      13f
10: call    jstring
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx                      # a name with an escape matches no method
    jnz     12f
    lea     json_methods(%rip), %r15
    call    jtable
    cmp     $-1, %rax
    je      12f
    mov     %eax, %ecx
    mov     $1, %eax
    shl     %cl, %rax
    or      %rax, EngineResponse_capabilities(%rbp)
12: call    jws
    cmp     %rbx, %rdi
    jae     9f
    movzbl  (%rdi), %eax
    inc     %rdi
    cmp     $']', %eax
    je      16f
    cmp     $',', %eax
    jne     9f
    call    jws
    jmp     10b
13: inc     %rdi
16: LEAVE 0
9:  xor     %edi, %edi
    LEAVE 0
END_FUNCTION jresult

/* L0: an error object at the cursor rdi, into rbp: rdi = the cursor after it. r14 1 when code is seen. */
LOCAL_FUNCTION jerror
    ENTER 0
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $'{', (%rdi)
    jne     9f
    inc     %rdi
    xor     %r14d, %r14d
    mov     $1, %esi
1:  call    jmember
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx
    jnz     8f
    JIS     json_code
    test    %eax, %eax
    jz      6f
    mov     %rdi, %r13                      # code: an integer from -2^63 to 2^63 - 1
    call    jnumber
    test    %rdi, %rdi
    jz      9f
    test    %rsi, %rsi
    jz      9f
    xor     %r15d, %r15d                    # 1 for a minus
    cmpb    $'-', (%r13)
    jne     2f
    mov     $1, %r15d
    inc     %r13
2:  xor     %eax, %eax
    mov     $10, %ecx
3:  cmp     %rdi, %r13
    jae     4f
    movzbl  (%r13), %r8d
    inc     %r13
    sub     $'0', %r8d
    mul     %rcx
    jc      9f
    add     %r8, %rax
    jc      9f
    jmp     3b
4:  mov     $0x7fffffffffffffff, %rdx       # the magnitude: at most 2^63, or 2^63 - 1
    add     %r15, %rdx
    cmp     %rdx, %rax
    ja      9f
    test    %r15, %r15
    jz      5f
    neg     %rax
5:  mov     %rax, EngineResponse_error_code(%rbp)
    mov     $1, %r14d
    jmp     7f
6:  call    jskip
    test    %rdi, %rdi
    jz      9f
7:  xor     %esi, %esi
    jmp     1b
8:  test    %r14, %r14
    jz      9f
    LEAVE 0
9:  xor     %edi, %edi
    LEAVE 0
END_FUNCTION jerror

/*
 * (body, method, out): rbx the end, rbp out, r12 method, r13 1 when id is seen, r14 1 for an
 * error, 2 for a result, r15 the body's first byte.
 */
FUNCTION lantern_engine_parse_response
    ENTER 0
    mov     8(%rdi), %rax
    mov     16(%rdi), %rbx
    add     %rax, %rdi
    add     %rdi, %rbx
    mov     %rdi, %r15
    mov     (%rsi), %r12
    mov     %rdx, %rbp
    xor     %eax, %eax                      # out: zero
1:  movq    $0, (%rbp,%rax)
    add     $8, %rax
    cmp     $EngineResponse__mem, %rax
    jb      1b
    xor     %r13d, %r13d
    xor     %r14d, %r14d
    call    jws
    cmp     %rbx, %rdi
    jae     9f
    cmpb    $'{', (%rdi)
    jne     9f
    inc     %rdi
    mov     $1, %esi
2:  call    jmember
    test    %rdi, %rdi
    jz      9f
    test    %rcx, %rcx
    jnz     8f
    JIS     json_id
    test    %eax, %eax
    jz      4f
    mov     %rdi, %r11                      # id: digits, at most 2^64 - 1
    call    jnumber
    test    %rdi, %rdi
    jz      9f
    test    %rsi, %rsi
    jz      9f
    cmpb    $'-', (%r11)
    je      9f
    xor     %eax, %eax
    mov     $10, %ecx
3:  cmp     %rdi, %r11
    jae     5f
    movzbl  (%r11), %r8d
    inc     %r11
    sub     $'0', %r8d
    mul     %rcx
    jc      9f
    add     %r8, %rax
    jc      9f
    jmp     3b
5:  mov     %rax, EngineResponse_id(%rbp)
    mov     $1, %r13d
    jmp     7f
4:  JIS     json_result
    test    %eax, %eax
    jz      6f
    call    jresult
    test    %rdi, %rdi
    jz      9f
    or      $2, %r14
    jmp     7f
6:  JIS     json_error
    test    %eax, %eax
    jz      10f
    call    jerror
    test    %rdi, %rdi
    jz      9f
    or      $1, %r14
    jmp     7f
10: call    jskip
    test    %rdi, %rdi
    jz      9f
7:  xor     %esi, %esi
    jmp     2b
8:  call    jws                             # then nothing but whitespace
    cmp     %rbx, %rdi
    jne     9f
    test    %r13, %r13
    jz      9f
    test    %r14, %r14
    jz      9f
    and     $1, %r14
    mov     %r14, EngineResponse_error(%rbp)
    xor     %eax, %eax
    LEAVE 0
9:  mov     $LANTERN_INVALID_JSON, %eax
    LEAVE 0
END_FUNCTION lantern_engine_parse_response
