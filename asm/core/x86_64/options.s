/*
 * The command line options of the binary, x86-64: in the common object. Requirements: docs/reference/app.md, lantern_app_options.
 */

    RODATA
.include "app_options.inc"

/* rax = 0 and rdx = the u64 of the decimal digits rdi to rsi, one or more; else rax = 1. Uses rcx, rdi, r8, r9. */
LOCAL_FUNCTION app_decimal
    UNWIND_END_PROLOGUE
    cmp     %rsi, %rdi
    jae     9f
    xor     %r8d, %r8d
1:  cmp     %rsi, %rdi
    jae     8f
    movzbl  (%rdi), %r9d
    inc     %rdi
    sub     $0x30, %r9d
    cmp     $9, %r9d
    ja      9f
    mov     %r8, %rax
    mov     $10, %ecx
    mul     %rcx
    jc      9f
    add     %r9, %rax
    jc      9f
    mov     %rax, %r8
    jmp     1b
8:  mov     %r8, %rdx
    xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION app_decimal

/*
 * rax = 0 and rdx = the IPv4 address of the bytes rdi to rsi, 4 decimal numbers of 0 to 255 with
 * dots between them, its 4 bytes in order in the low bytes; else rax = 1. Uses rcx, rdi, r8-r11.
 */
LOCAL_FUNCTION app_ipv4
    UNWIND_END_PROLOGUE
    xor     %r8d, %r8d                      # the address
    xor     %r9d, %r9d                      # the numbers
    xor     %ecx, %ecx                      # the shift of the next one
1:  xor     %r10d, %r10d                    # a number
    xor     %r11d, %r11d                    # its digits
2:  cmp     %rsi, %rdi
    jae     3f
    movzbl  (%rdi), %eax
    cmp     $0x2e, %eax                     # .
    je      3f
    sub     $0x30, %eax
    cmp     $9, %eax
    ja      9f
    inc     %r11
    cmp     $3, %r11
    ja      9f
    lea     (%r10,%r10,4), %r10
    add     %r10, %r10
    add     %rax, %r10
    inc     %rdi
    jmp     2b
3:  test    %r11, %r11
    jz      9f
    cmp     $255, %r10
    ja      9f
    shl     %cl, %r10
    or      %r10, %r8
    add     $8, %ecx
    inc     %r9
    cmp     %rsi, %rdi
    jae     4f
    inc     %rdi                            # past the dot, to the next number
    cmp     $4, %r9
    jae     9f
    jmp     1b
4:  cmp     $4, %r9
    jne     9f
    mov     %r8, %rdx
    xor     %eax, %eax
    ret
9:  mov     $1, %eax
    ret
END_FUNCTION app_ipv4

/*
 * (args, options, fault): docs/reference/app.md. rbx args, rbp options, r12 fault, r13 the
 * argument count, r14 the next argument, r15 the Arg entries, S7 an option record, S8 the
 * value's start, S9 its length, S10 the argument that holds it. Locals: L the name's start,
 * L+8 its length, L+16 the option's argument, L+24 a log level.
 */
FUNCTION lantern_app_options
    ENTER 32
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rbp, %rdi                      # the defaults
    mov     $AppOptions__size, %esi
    call    lantern_zero
    movq    $APP_DEFAULT_PORT, AppOptions_port(%rbp)
    movq    $APP_DEFAULT_HTTP_PORT, AppOptions_http_port(%rbp)
    movq    $APP_DEFAULT_TARGET_PEERS, AppOptions_target_peers(%rbp)
    movq    $APP_DEFAULT_LOG_LEVEL, AppOptions_log_level(%rbp)
    movq    $APP_DEFAULT_HTTP_ADDRESS, AppOptions_http_address(%rbp)
    movq    $APP_DEFAULT_HTTP_CONNECTIONS, AppOptions_http_max_connections(%rbp)
    mov     (ArgList_args + 8)(%rbx), %r13
    mov     ArgList_args(%rbx), %r15
    add     %rbx, %r15
    xor     %r14d, %r14d
1:  cmp     %r13, %r14                      # the next option: --name value or --name=value
    jae     50f
    mov     %r14, (L + 16)(%rsp)
    mov     %r14, S10(%rsp)
    mov     %r14, %rax
    shl     $4, %rax
    mov     (%r15,%rax), %r10
    mov     8(%r15,%rax), %r11
    cmp     $3, %r11
    jb      91f
    cmpb    $0x2d, (%rbx,%r10)
    jne     91f
    cmpb    $0x2d, 1(%rbx,%r10)
    jne     91f
    add     $2, %r10
    sub     $2, %r11
    mov     %r10, L(%rsp)
    xor     %ecx, %ecx
2:  cmp     %r11, %rcx                      # the name: up to = or the end
    jae     3f
    lea     (%rbx,%r10), %rax
    cmpb    $0x3d, (%rax,%rcx)              # =
    je      3f
    inc     %rcx
    jmp     2b
3:  mov     %rcx, (L + 8)(%rsp)
    mov     %rcx, S8(%rsp)                  # S8: where = is, S9: the length of the name and value
    mov     %r11, S9(%rsp)
    lea     app_options(%rip), %rax
    mov     %rax, S7(%rsp)
6:  mov     S7(%rsp), %rdx
    lea     app_options_end(%rip), %rax
    cmp     %rax, %rdx
    jae     91f                             # not an option
    mov     L(%rsp), %rdi
    add     %rbx, %rdi
    mov     (L + 8)(%rsp), %rsi
    mov     (%rdx), %rcx
    add     $24, %rdx
    call    config_name_is
    test    %rax, %rax
    jnz     4f
    addq    $APP_OPTION_BYTES, S7(%rsp)
    jmp     6b
4:  mov     S7(%rsp), %rax
    cmpq    $APP_OPTION_FLAG, 16(%rax)
    jne     5f
    mov     S8(%rsp), %rax                  # a flag: no value, 1
    cmp     S9(%rsp), %rax
    jne     90f
    inc     %r14
    mov     $1, %edx
    jmp     23f
5:  mov     S8(%rsp), %rax
    cmp     S9(%rsp), %rax
    jne     51f
    lea     1(%r14), %rax                   # --name value: the value is the next argument
    mov     %rax, S10(%rsp)
    cmp     %r13, %rax
    jae     91f
    shl     $4, %rax
    mov     (%r15,%rax), %rcx
    mov     %rcx, S8(%rsp)
    mov     8(%r15,%rax), %rcx
    mov     %rcx, S9(%rsp)
    add     $2, %r14
    jmp     7f
51: mov     S9(%rsp), %rax                  # --name=value
    sub     S8(%rsp), %rax
    dec     %rax
    mov     %rax, S9(%rsp)
    mov     L(%rsp), %rax
    add     S8(%rsp), %rax
    inc     %rax
    mov     %rax, S8(%rsp)
    inc     %r14
7:  cmpq    $0, S9(%rsp)                    # an empty value
    je      90f
    mov     S7(%rsp), %rax
    mov     16(%rax), %rax
    cmp     $APP_OPTION_ENDPOINT, %rax
    ja      20f
    jne     8f
    cmpq    $7, S9(%rsp)                    # the endpoint: without http://
    jb      8f
    mov     S8(%rsp), %rdi
    add     %rbx, %rdi
    mov     $7, %esi
    lea     app_http(%rip), %rdx
    mov     $7, %ecx
    call    config_name_is
    test    %rax, %rax
    jz      8f
    addq    $7, S8(%rsp)
    subq    $7, S9(%rsp)
    jz      90f
8:  mov     S7(%rsp), %rax                  # a text: its Arg
    mov     8(%rax), %rax
    mov     S8(%rsp), %rcx
    mov     %rcx, (%rbp,%rax)
    mov     S9(%rsp), %rcx
    mov     %rcx, 8(%rbp,%rax)
    jmp     1b
20: cmp     $APP_OPTION_LEVEL, %rax
    je      24f
    mov     S8(%rsp), %rdi                  # a number, or an address
    add     %rbx, %rdi
    mov     S9(%rsp), %rsi
    add     %rdi, %rsi
    cmp     $APP_OPTION_ADDRESS, %rax
    je      21f
    call    app_decimal
    test    %rax, %rax
    jnz     90f
    test    %rdx, %rdx
    jz      90f
    mov     S7(%rsp), %rax
    mov     $65535, %ecx
    cmpq    $APP_OPTION_PORT, 16(%rax)
    je      22f
    mov     $APP_MAX_TARGET_PEERS, %ecx
    cmpq    $APP_OPTION_CONNECTIONS, 16(%rax)
    jne     22f
    mov     $APP_MAX_HTTP_CONNECTIONS, %ecx
22: cmp     %rcx, %rdx
    ja      90f
    jmp     23f
21: call    app_ipv4
    test    %rax, %rax
    jnz     90f
23: mov     S7(%rsp), %rax
    mov     8(%rax), %rax
    mov     %rdx, (%rbp,%rax)
    jmp     1b
24: movq    $0, (L + 24)(%rsp)              # a log level: one of the names of app_levels
25: mov     (L + 24)(%rsp), %rcx
    cmp     $4, %rcx
    jae     90f
    mov     S8(%rsp), %rdi
    add     %rbx, %rdi
    mov     S9(%rsp), %rsi
    ADDRESS %rdx, app_levels
    lea     (%rdx,%rcx,8), %rdx
    ADDRESS %rax, app_level_lengths
    movzbl  (%rax,%rcx), %ecx
    call    config_name_is
    test    %rax, %rax
    jnz     26f
    incq    (L + 24)(%rsp)
    jmp     25b
26: mov     (L + 24)(%rsp), %rdx
    jmp     23b
50: mov     %r13, S10(%rsp)                 # --network-dir is required
    cmpq    $0, (AppOptions_network_dir + 8)(%rbp)
    je      90f
    cmpq    $0, (AppOptions_checkpoint_state + 8)(%rbp) # --checkpoint-state and --checkpoint-block go together
    sete    %al
    cmpq    $0, (AppOptions_checkpoint_block + 8)(%rbp)
    sete    %cl
    cmp     %al, %cl
    jne     90f
    cmpq    $0, AppOptions_archive(%rbp)    # --archive needs --data-dir
    je      51f
    cmpq    $0, (AppOptions_data_dir + 8)(%rbp)
    je      90f
51: movq    $0, (%r12)
    xor     %eax, %eax
    LEAVE 32
91: mov     (L + 16)(%rsp), %rax            # a fault of the option's argument
    mov     %rax, S10(%rsp)
90: mov     S10(%rsp), %rax                 # a fault of the value's argument
    mov     %rax, (%r12)
    mov     $LANTERN_INVALID_OPTION, %eax
    LEAVE 32
END_FUNCTION lantern_app_options
