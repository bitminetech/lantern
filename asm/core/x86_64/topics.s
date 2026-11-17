/*
 * Gossip topic strings, x86-64: in the common object. Requirements: docs/reference/networking.md.
 */

/*
 * al = the lowercase hex digit of the value 0 to 15 in eax. In a macro with no parameters,
 * the macOS assembler reads $1 to $9 as macro arguments, so the immediate is $(10).
 */
.macro HEX_DIGIT
    cmp     $(10), %eax
    jb      91f
    add     $('a' - 10 - '0'), %eax
91: add     $'0', %eax
.endm

/*
 * (topic, out): /eth2/ + hex(fork_digest) + / + name [+ _ + subnet_id] + /ssz_snappy.
 * r8 the name entry, r9 the string length, r10 a subnet topic, r11 the subnet's digits;
 * rax, rcx, rdx, rdi work; rsi the write pointer after the room check.
 */
FUNCTION lantern_gossip_topic
    UNWIND_END_PROLOGUE
    mov     GossipTopic_name(%rdi), %rax
    dec     %rax
    cmp     $GOSSIP_NAMES, %rax
    jae     9f
    shl     $4, %rax
    lea     gossip_names(%rip), %r8
    add     %rax, %r8
    mov     8(%r8), %r9                     # the name's length; bit 63: a subnet topic
    mov     %r9, %r10
    shr     $63, %r10
    and     $0xff, %r9d
    add     $(6 + 8 + 1 + 11), %r9
    xor     %r11d, %r11d                    # digits of the subnet
    test    %r10, %r10
    jz      2f
    mov     GossipTopic_subnet_id(%rdi), %rax
    mov     $10, %ecx
1:  xor     %edx, %edx
    div     %rcx
    inc     %r11
    test    %rax, %rax
    jnz     1b
    lea     1(%r9,%r11), %r9
2:  mov     (%rsi), %rax                    # room for the string
    sub     $24, %rax
    jb      8f
    cmp     %r9, %rax
    jb      8f
    movq    $24, 8(%rsi)
    mov     %r9, 16(%rsi)
    mov     %rdi, %rdx                      # the topic; the string is written with stosb
    lea     24(%rsi), %rdi
    lea     gossip_prefix(%rip), %rsi       # /eth2/
    mov     $6, %ecx
    rep movsb
    xor     %ecx, %ecx                      # the digest's 4 bytes, as lowercase hex
3:  movzbl  (%rdx,%rcx), %eax
    shr     $4, %eax
    HEX_DIGIT
    stosb
    movzbl  (%rdx,%rcx), %eax
    and     $15, %eax
    HEX_DIGIT
    stosb
    inc     %ecx
    cmp     $4, %ecx
    jb      3b
    movb    $'/', %al
    stosb
    lea     gossip_name_bytes(%rip), %rsi   # the name
    add     (%r8), %rsi
    mov     8(%r8), %rcx
    and     $0xff, %ecx
    rep movsb
    test    %r10, %r10
    jz      6f
    movb    $'_', %al                       # _ + subnet_id in decimal, written from its last digit
    stosb
    add     %r11, %rdi
    mov     %rdi, %rsi
    mov     GossipTopic_subnet_id(%rdx), %rax
    mov     $10, %ecx
5:  xor     %edx, %edx
    div     %rcx
    add     $'0', %dl
    dec     %rsi
    mov     %dl, (%rsi)
    dec     %r11
    jnz     5b
6:  lea     gossip_suffix(%rip), %rsi       # /ssz_snappy
    mov     $11, %ecx
    rep movsb
    xor     %eax, %eax
    ret
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    ret
9:  mov     $LANTERN_INVALID_TOPIC, %eax
    ret
END_FUNCTION lantern_gossip_topic


/*
 * (string, out): the topic of a string that lantern_gossip_topic writes.
 * rdi the bytes, rdx their count, r8 the digest, r9 the name part, r10 its length, r11 the name,
 * r13 out, rbx the name entry then its subnet flag, rbp the name's bytes, r12 its length,
 * rsi the subnet; rax, rcx work.
 */
FUNCTION lantern_gossip_topic_parse
    push    %rbx
    UNWIND_PUSH %rbx
    push    %rbp
    UNWIND_PUSH %rbp
    push    %r12
    UNWIND_PUSH %r12
    push    %r13
    UNWIND_PUSH %r13
    UNWIND_END_PROLOGUE
    mov     %rsi, %r13
    mov     8(%rdi), %rax
    mov     16(%rdi), %rdx
    add     %rax, %rdi
    cmp     $(6 + 8 + 1 + 1 + 11), %rdx
    jb      9f
    lea     gossip_prefix(%rip), %rbx       # /eth2/
    xor     %ecx, %ecx
1:  movzbl  (%rdi,%rcx), %eax
    cmp     (%rbx,%rcx), %al
    jne     9f
    inc     %ecx
    cmp     $6, %ecx
    jb      1b
    xor     %r8d, %r8d                      # 8 lowercase hex digits
    mov     $6, %ecx
2:  movzbl  (%rdi,%rcx), %eax
    sub     $'0', %eax
    cmp     $10, %eax
    jb      3f
    movzbl  (%rdi,%rcx), %eax
    sub     $'a', %eax
    cmp     $6, %eax
    jae     9f
    add     $10, %eax
3:  shl     $4, %r8
    or      %rax, %r8
    inc     %ecx
    cmp     $14, %ecx
    jb      2b
    cmpb    $'/', 14(%rdi)
    jne     9f
    lea     gossip_suffix(%rip), %rbx       # /ssz_snappy at the end
    lea     -11(%rdi,%rdx), %rbp
    xor     %ecx, %ecx
4:  movzbl  (%rbp,%rcx), %eax
    cmp     (%rbx,%rcx), %al
    jne     9f
    inc     %ecx
    cmp     $11, %ecx
    jb      4b
    lea     15(%rdi), %r9                   # the name part: from 15 to the suffix
    lea     -(15 + 11)(%rdx), %r10
    mov     $1, %r11d                       # each name in turn
5:  lea     -1(%r11), %rax
    shl     $4, %rax
    lea     gossip_names(%rip), %rbx
    add     %rax, %rbx
    lea     gossip_name_bytes(%rip), %rbp
    add     (%rbx), %rbp                    # the name's bytes
    mov     8(%rbx), %r12
    mov     %r12, %rbx
    shr     $63, %rbx                       # a subnet topic
    and     $0xff, %r12d                    # the name's length
    cmp     %r12, %r10                      # the name part starts with the name
    jb      7f
    xor     %ecx, %ecx
6:  movzbl  (%r9,%rcx), %eax
    cmp     (%rbp,%rcx), %al
    jne     7f
    inc     %rcx
    cmp     %r12, %rcx
    jb      6b
    xor     %esi, %esi                      # the subnet
    cmp     %r12, %r10                      # exactly the name: a topic without a subnet
    jne     10f
    test    %rbx, %rbx
    jnz     7f
    jmp     12f
10: test    %rbx, %rbx                      # name + _ + canonical decimal
    jz      7f
    lea     1(%r12), %rcx
    cmp     %rcx, %r10
    jbe     7f
    cmpb    $'_', (%r9,%r12)
    jne     7f
    cmpb    $'0', (%r9,%rcx)                # a leading zero
    jne     11f
    lea     1(%rcx), %rax
    cmp     %rax, %r10
    jne     7f
11: movzbl  (%r9,%rcx), %ebp
    sub     $'0', %ebp
    cmp     $10, %ebp
    jae     7f
    mov     %rsi, %rax
    mov     $10, %r12d
    mul     %r12
    jc      7f
    add     %rbp, %rax
    jc      7f
    mov     %rax, %rsi
    inc     %rcx
    cmp     %r10, %rcx
    jb      11b
12: bswap   %r8d                            # the digest's bytes in order
    mov     %r8, GossipTopic_fork_digest(%r13)
    mov     %r11, GossipTopic_name(%r13)
    mov     %rsi, GossipTopic_subnet_id(%r13)
    xor     %eax, %eax
    jmp     13f
7:  inc     %r11
    cmp     $GOSSIP_NAMES, %r11
    jbe     5b
9:  mov     $LANTERN_INVALID_TOPIC, %eax
13: UNWIND_BEGIN_EPILOGUE
    pop     %r13
    UNWIND_POP %r13
    pop     %r12
    UNWIND_POP %r12
    pop     %rbp
    UNWIND_POP %rbp
    pop     %rbx
    UNWIND_POP %rbx
    UNWIND_END_EPILOGUE
    ret
END_FUNCTION lantern_gossip_topic_parse

GOSSIP_TOPIC_DATA
