/*
 * Req/resp encoding, x86-64: in the common object. Requirements: docs/reference/req-resp.md.
 */

/* (id, out): the method and version of /eth2/beacon_chain/req/<name>/<version>/ssz_snappy. */
FUNCTION lantern_reqresp_protocol_parse
    UNWIND_END_PROLOGUE
    mov     8(%rdi), %rax
    mov     16(%rdi), %rdx                  # the count
    add     %rax, %rdi                      # the bytes
    cmp     $(23 + 1 + 1 + 1 + 11), %rdx
    jb      9f
    lea     reqresp_prefix(%rip), %r8       # the prefix
    xor     %ecx, %ecx
1:  movzbl  (%rdi,%rcx), %eax
    cmp     (%r8,%rcx), %al
    jne     9f
    inc     %ecx
    cmp     $23, %ecx
    jb      1b
    lea     gossip_suffix(%rip), %r8        # /ssz_snappy at the end
    lea     -11(%rdi,%rdx), %r9
    xor     %ecx, %ecx
2:  movzbl  (%r9,%rcx), %eax
    cmp     (%r8,%rcx), %al
    jne     9f
    inc     %ecx
    cmp     $11, %ecx
    jb      2b
    lea     23(%rdi), %r8                   # name / version: the version is one digit, 1 to 9
    lea     -(23 + 11 + 2)(%rdx), %r9       # the name's length
    cmpb    $'/', (%r8,%r9)
    jne     9f
    movzbl  1(%r8,%r9), %r10d
    sub     $'1', %r10d
    cmp     $9, %r10d
    jae     9f
    inc     %r10d                           # the version
    mov     $1, %r11d                       # each method in turn
3:  lea     -1(%r11), %rax
    shl     $4, %rax
    lea     reqresp_names(%rip), %rcx
    add     %rax, %rcx
    movzbl  8(%rcx), %eax                   # the name's length
    cmp     %r9, %rax
    jne     5f
    mov     (%rcx), %rdx
    lea     reqresp_name_bytes(%rip), %rax
    add     %rax, %rdx
    xor     %eax, %eax
4:  movzbl  (%r8,%rax), %edi
    cmp     (%rdx,%rax), %dil
    jne     5f
    inc     %rax
    cmp     %r9, %rax
    jb      4b
    mov     8(%rcx), %rax                   # the method has the version
    shr     $8, %rax
    bt      %r10, %rax
    jnc     9f
    mov     %r11, (%rsi)
    mov     %r10, 8(%rsi)
    xor     %eax, %eax
    ret
5:  inc     %r11
    cmp     $REQRESP_METHODS, %r11
    jbe     3b
9:  mov     $LANTERN_INVALID_PROTOCOL, %eax
    ret
END_FUNCTION lantern_reqresp_protocol_parse

/* (protocol, out): /eth2/beacon_chain/req/ + name + / + version + /ssz_snappy. */
FUNCTION lantern_reqresp_protocol_id
    UNWIND_END_PROLOGUE
    mov     (%rdi), %rax                    # method
    mov     8(%rdi), %rdx                   # version
    dec     %rax
    cmp     $REQRESP_METHODS, %rax
    jae     9f
    cmp     $10, %rdx
    jae     9f
    shl     $4, %rax
    lea     reqresp_names(%rip), %r8
    add     %rax, %r8
    mov     8(%r8), %rax
    shr     $8, %rax
    bt      %rdx, %rax
    jnc     9f
    movzbl  8(%r8), %r9d                    # the name's length
    lea     (23 + 2 + 11)(%r9), %r10        # the ID's length
    mov     (%rsi), %rax
    sub     $24, %rax
    jb      8f
    cmp     %r10, %rax
    jb      8f
    movq    $24, 8(%rsi)
    mov     %r10, 16(%rsi)
    lea     24(%rsi), %rdi
    lea     reqresp_prefix(%rip), %rsi
    mov     $23, %ecx
    rep movsb
    lea     reqresp_name_bytes(%rip), %rsi
    add     (%r8), %rsi
    mov     %r9, %rcx
    rep movsb
    movb    $'/', (%rdi)
    lea     '0'(%rdx), %eax
    mov     %al, 1(%rdi)
    add     $2, %rdi
    lea     gossip_suffix(%rip), %rsi
    mov     $11, %ecx
    rep movsb
    xor     %eax, %eax
    ret
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    ret
9:  mov     $LANTERN_INVALID_PROTOCOL, %eax
    ret
END_FUNCTION lantern_reqresp_protocol_id

/* rax = the chunk bound of rax payload bytes: 25 + n + 8 * ceil(n / 65536); carry set on overflow. Uses rcx. */
LOCAL_FUNCTION lantern_chunk_bound
    UNWIND_END_PROLOGUE
    mov     %rax, %rcx
    shr     $16, %rcx
    test    $0xffff, %eax
    jz      1f
    inc     %rcx
1:  add     $25, %rax
    jc      2f
    shl     $3, %rcx
    add     %rcx, %rax
2:  ret
END_FUNCTION lantern_chunk_bound

FUNCTION lantern_reqresp_chunk_size
    UNWIND_END_PROLOGUE
    mov     (%rdi), %rax
    call    lantern_chunk_bound
    jc      9f
    mov     %rax, (%rsi)
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_reqresp_chunk_size

/*
 * rbx header, rbp payload, r12 scratch, r13 out, r14 the payload's length, r15 the header's
 * length, S7 where the chunk starts, S8 the frames' ByteList in scratch.
 */
FUNCTION lantern_reqresp_write_chunk
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rcx, %r13
    mov     16(%rbp), %r14
    mov     %r14, %rax
    call    lantern_chunk_bound
    jc      8f
    mov     (%r13), %rcx                    # room in out: size - offset - count
    sub     8(%r13), %rcx
    jb      8f
    sub     16(%r13), %rcx
    jb      8f
    cmp     %rax, %rcx
    jb      8f
    add     $(SNAPPY_SCRATCH_FRAME + 24), %rax   # scratch: asm-snappy's, then the frames
    jc      8f
    cmp     %rax, (%r12)
    jb      8f
    mov     8(%r13), %rdi
    add     16(%r13), %rdi
    add     %r13, %rdi                      # where the chunk starts
    xor     %r15d, %r15d                    # the result byte and the context bytes of a response
    cmpq    $0, ChunkHeader_kind(%rbx)
    je      2f
    mov     ChunkHeader_result(%rbx), %rax
    mov     %al, (%rdi)
    inc     %rdi
    inc     %r15
    test    %rax, %rax
    jnz     2f
    cmpq    $0, ChunkHeader_context_length(%rbx)
    je      2f
    mov     ChunkHeader_context(%rbx), %eax
    mov     %eax, (%rdi)
    add     $4, %rdi
    add     $4, %r15
2:  mov     %r14, %rax                      # the length as the shortest unsigned varint
3:  cmp     $0x80, %rax
    jb      4f
    mov     %al, %cl
    or      $0x80, %cl
    mov     %cl, (%rdi)
    inc     %rdi
    shr     $7, %rax
    inc     %r15
    jmp     3b
4:  mov     %al, (%rdi)
    inc     %rdi
    inc     %r15
    mov     %rdi, S7(%rsp)
    test    %r14, %r14                      # an empty payload has no frame
    jz      6f
    lea     SNAPPY_SCRATCH_FRAME(%r12), %rdx
    mov     %rdx, S8(%rsp)
    mov     (%r12), %rax
    sub     $SNAPPY_SCRATCH_FRAME, %rax
    mov     %rax, (%rdx)                    # the frames' ByteList: the rest of scratch
    movq    $SNAPPY_SCRATCH_FRAME, (%r12)   # asm-snappy's scratch: its first bytes
    mov     %rbp, %rdi
    mov     %r12, %rsi
    CALL_GLOBAL snappy_frame_compress
    test    %rax, %rax
    jnz     8f
    mov     S8(%rsp), %rsi                  # the frames after the header
    mov     16(%rsi), %rdx
    add     %rdx, %r15
    add     8(%rsi), %rsi
    mov     S7(%rsp), %rdi
    call    lantern_copy
6:  add     %r15, 16(%r13)
    xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
END_FUNCTION lantern_reqresp_write_chunk

/* (input, header): rdi the bytes, rdx their count, r11 the position, r8 result, r9 context, r10 length, rcx shift. */
FUNCTION lantern_reqresp_read_header
    UNWIND_END_PROLOGUE
    mov     8(%rdi), %rax
    mov     16(%rdi), %rdx
    add     %rax, %rdi
    xor     %r11d, %r11d
    xor     %r8d, %r8d
    xor     %r9d, %r9d
    cmpq    $0, ChunkHeader_kind(%rsi)
    je      2f
    test    %rdx, %rdx                      # the result byte
    jz      7f
    movzbl  (%rdi), %r8d
    mov     $1, %r11d
    test    %r8, %r8
    jnz     2f
    cmpq    $0, ChunkHeader_context_length(%rsi)
    je      2f
    cmp     $5, %rdx                        # the context bytes
    jb      7f
    mov     1(%rdi), %r9d
    mov     $5, %r11d
2:  xor     %r10d, %r10d                    # the varint: at most 10 bytes, at most 2^64 - 1
    xor     %ecx, %ecx
3:  cmp     %rdx, %r11
    jae     7f
    movzbl  (%rdi,%r11), %eax
    inc     %r11
    cmp     $63, %ecx
    je      5f
    and     $0x7f, %eax
    shl     %cl, %rax
    or      %rax, %r10
    testb   $0x80, -1(%rdi,%r11)
    jz      6f
    add     $7, %ecx
    jmp     3b
5:  cmp     $1, %eax                        # the tenth byte gives bit 63 only
    ja      8f
    shl     $63, %rax
    or      %rax, %r10
6:  mov     %r8, ChunkHeader_result(%rsi)
    mov     %r9, ChunkHeader_context(%rsi)
    mov     %r10, ChunkHeader_length(%rsi)
    mov     %r11, ChunkHeader_header_bytes(%rsi)
    xor     %eax, %eax
    ret
7:  mov     $LANTERN_REQRESP_MORE, %eax
    ret
8:  mov     $LANTERN_INVALID_CHUNK, %eax
    ret
END_FUNCTION lantern_reqresp_read_header

/*
 * rbx input, rbp start, r12 length, r13 eof, r14 scratch, r15 out, S7 consumed,
 * S8 the bytes after start, S9 max_compressed_len(length). Locals: L the length, for asm-snappy.
 * The 7th argument, consumed, is on the stack.
 */
FUNCTION lantern_reqresp_read_payload
    ENTER 16
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     (%rdx), %r12
    mov     (%rcx), %r13
    mov     %r8, %r14
    mov     %r9, %r15
    mov     (16 + 96)(%rsp), %rax           # the seventh argument
    mov     %rax, S7(%rsp)
    mov     %r12, L(%rsp)
    mov     (%r15), %rax                    # out has room for length bytes
    sub     $24, %rax
    jb      8f
    cmp     %r12, %rax
    jb      8f
    mov     16(%rbx), %rax
    sub     %rbp, %rax
    jb      9f                              # start after the end of input
    mov     %rax, S8(%rsp)
    mov     %r12, %rax                      # max_compressed_len(length), 2^64 - 1 on overflow
    xor     %edx, %edx
    mov     $6, %ecx
    div     %rcx
    mov     %r12, %rcx
    add     $32, %rcx
    jc      1f
    add     %rax, %rcx
    jnc     2f
1:  mov     $-1, %rcx
2:  mov     %rcx, S9(%rsp)
    mov     S8(%rsp), %rdx                  # the bytes read: the fewer of the two
    cmp     %rcx, %rdx
    cmova   %rcx, %rdx
    lea     (24 + 7)(%rdx), %rax            # scratch: a ByteList of those bytes
    and     $-8, %rax
    cmp     %rdx, %rax
    jb      8f
    cmp     %rax, (%r14)
    jb      8f
    movq    $24, 8(%r14)
    mov     %rdx, 16(%r14)
    lea     24(%r14), %rdi
    mov     8(%rbx), %rsi
    add     %rbx, %rsi
    add     %rbp, %rsi
    call    lantern_copy
    mov     %r14, %rdi
    lea     L(%rsp), %rsi
    mov     %r15, %rdx
    mov     S7(%rsp), %rcx
    CALL_GLOBAL snappy_frame_uncompress
    test    %rax, %rax
    jz      7f
    cmp     $SNAPPY_BUFFER_TOO_SMALL, %rax
    je      8f
    cmp     $SNAPPY_TRUNCATED, %rax         # truncated within the bound, with more bytes to come
    jne     9f
    mov     S8(%rsp), %rax
    cmp     S9(%rsp), %rax
    jae     9f
    test    %r13, %r13
    jnz     9f
    mov     $LANTERN_REQRESP_MORE, %eax
7:  LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
9:  mov     $LANTERN_INVALID_CHUNK, %eax
    LEAVE 16
END_FUNCTION lantern_reqresp_read_payload

/* rax = rax + rcx, or 2^64 - 1 on overflow. */
.macro SAT_ADD
    add     %rcx, %rax
    jnc     91f
    mov     $-1, %rax
91:
.endm

/* rax = rax * rcx, or 2^64 - 1 on overflow. Uses rdx. */
.macro SAT_MUL
    mul     %rcx
    jno     92f
    mov     $-1, %rax
92:
.endm

/*
 * (rdi descriptor, rsi node) -> rax min, rdx max, saturating at 2^64 - 1.
 * rbx descriptor, rbp node, r12 length or the last field, r13 element or field, r14 min, r15 max.
 */
LOCAL_FUNCTION lantern_size_bounds
    ENTER 0
    mov     %rdi, %rbx
    imul    $SSZ_NODE_STRIDE, %rsi, %rbp
    add     SSZ_DESC_NODES_OFFSET(%rbx), %rbp
    add     %rbx, %rbp
    mov     SSZ_NODE_SSZ_SIZE(%rbp), %rax   # a fixed size type
    mov     %rax, %rdx
    test    %rax, %rax
    jnz     9f
    mov     SSZ_NODE_LENGTH(%rbp), %r12
    mov     SSZ_NODE_KIND(%rbp), %rcx
    cmp     $SSZ_KIND_BIT_LIST, %rcx
    jne     1f
    mov     $1, %eax
    mov     %r12, %rdx
    shr     $3, %rdx
    inc     %rdx
    jmp     9f
1:  cmp     $SSZ_KIND_BYTE_LIST, %rcx
    jne     2f
    xor     %eax, %eax
    mov     %r12, %rdx
    jmp     9f
2:  cmp     $SSZ_KIND_CONTAINER, %rcx
    je      5f
    mov     SSZ_NODE_ELEMENT(%rbp), %r13    # a list or a vector: its element
    mov     %rbx, %rdi
    mov     %r13, %rsi
    call    lantern_size_bounds
    mov     %rax, %r14
    mov     %rdx, %r15
    imul    $SSZ_NODE_STRIDE, %r13, %rcx
    add     SSZ_DESC_NODES_OFFSET(%rbx), %rcx
    mov     SSZ_NODE_SSZ_SIZE(%rbx,%rcx), %r13  # the element's fixed size, or 0
    cmpq    $SSZ_KIND_LIST, SSZ_NODE_KIND(%rbp)
    jne     3f
    mov     %r15, %rax                      # a list: limit * (max, plus 4 for a variable element)
    test    %r13, %r13
    jnz     4f
    mov     $4, %ecx
    SAT_ADD
4:  mov     %r12, %rcx
    SAT_MUL
    mov     %rax, %rdx
    xor     %eax, %eax
    jmp     9f
3:  mov     %r14, %rax                      # a vector of variable elements: length * (4 + bound)
    mov     $4, %ecx
    SAT_ADD
    mov     %r12, %rcx
    SAT_MUL
    mov     %rax, %r14
    mov     %r15, %rax
    mov     $4, %ecx
    SAT_ADD
    mov     %r12, %rcx
    SAT_MUL
    mov     %rax, %rdx
    mov     %r14, %rax
    jmp     9f
5:  mov     SSZ_NODE_ELEMENT(%rbp), %r13    # a variable container: each field
    add     %r13, %r12
    xor     %r14d, %r14d
    xor     %r15d, %r15d
6:  cmp     %r12, %r13
    jae     8f
    mov     %r13, %rcx
    shl     $5, %rcx
    add     SSZ_DESC_FIELDS_OFFSET(%rbx), %rcx
    add     %rbx, %rcx
    mov     SSZ_FIELD_NODE(%rcx), %rsi
    testq   $SSZ_FIELD_VARIABLE, SSZ_FIELD_FLAGS(%rcx)
    jz      7f
    mov     %rbx, %rdi
    call    lantern_size_bounds                     # a variable field: its offset and its bounds
    mov     %rdx, S7(%rsp)
    mov     $4, %ecx
    SAT_ADD
    mov     %rax, %rcx
    mov     %r14, %rax
    SAT_ADD
    mov     %rax, %r14
    mov     S7(%rsp), %rax
    mov     $4, %ecx
    SAT_ADD
    mov     %rax, %rcx
    mov     %r15, %rax
    SAT_ADD
    mov     %rax, %r15
    inc     %r13
    jmp     6b
7:  imul    $SSZ_NODE_STRIDE, %rsi, %rcx    # a fixed field
    add     SSZ_DESC_NODES_OFFSET(%rbx), %rcx
    mov     SSZ_NODE_SSZ_SIZE(%rbx,%rcx), %rcx
    mov     %r14, %rax
    SAT_ADD
    mov     %rax, %r14
    mov     %r15, %rax
    SAT_ADD
    mov     %rax, %r15
    inc     %r13
    jmp     6b
8:  mov     %r14, %rax
    mov     %r15, %rdx
9:  LEAVE 0
END_FUNCTION lantern_size_bounds

FUNCTION lantern_ssz_size_bounds
    push    %rbx
    UNWIND_PUSH %rbx
    UNWIND_END_PROLOGUE
    mov     %rsi, %rbx
    mov     SSZ_DESC_ROOT(%rdi), %rsi
    call    lantern_size_bounds
    mov     %rax, (%rbx)
    mov     %rdx, 8(%rbx)
    xor     %eax, %eax
    UNWIND_BEGIN_EPILOGUE
    pop     %rbx
    UNWIND_POP %rbx
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION lantern_ssz_size_bounds

REQRESP_PROTOCOL_DATA
