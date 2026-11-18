/*
 * The index of the stored history, x86-64: in the common object. Requirements: docs/reference/db.md.
 */

# (room, size): DB_FIXED + the room of each part; roots a power of two. A leaf; uses rax, rcx, rdx, r8.
FUNCTION lantern_db_size
    UNWIND_END_PROLOGUE
    mov     DbRoom_roots(%rdi), %rax
    test    %rax, %rax
    jz      9f
    lea     -1(%rax), %rcx
    test    %rcx, %rax
    jnz     9f
    mov     %rax, %rcx
    shr     $61, %rcx
    jnz     9f
    lea     (,%rax,8), %r8
    mov     DbRoom_slots(%rdi), %rax
    mov     $DbSlot__mem, %ecx
    mul     %rcx
    jc      9f
    add     %rax, %r8
    jc      9f
    add     $DB_FIXED, %r8
    jc      9f
    mov     %r8, (%rsi)
    xor     %eax, %eax
    ret
9:  mov     $LANTERN_INVALID_OVERFLOW, %eax
    ret
END_FUNCTION lantern_db_size

# The parts of the Db rdi for the room rsi: slots at DB_FIXED, then roots; their counts the capacities. Uses rax.
LOCAL_FUNCTION db_layout
    UNWIND_END_PROLOGUE
    mov     DbRoom_slots(%rsi), %rax
    movq    $DB_FIXED, Db_slots(%rdi)
    mov     %rax, (Db_slots + 8)(%rdi)
    imul    $DbSlot__mem, %rax, %rax
    add     $DB_FIXED, %rax
    mov     %rax, Db_roots(%rdi)
    mov     DbRoom_roots(%rsi), %rax
    mov     %rax, (Db_roots + 8)(%rdi)
    ret
END_FUNCTION db_layout

# The root at rsi goes in the root table of the Db rdi with the value rdx, at the first free entry from its first 8 bytes. Uses rax, r8, r9.
LOCAL_FUNCTION db_insert
    UNWIND_END_PROLOGUE
    mov     Db_roots(%rdi), %r8
    add     %rdi, %r8
    mov     (Db_roots + 8)(%rdi), %r9
    dec     %r9
    mov     (%rsi), %rax
    and     %r9, %rax
1:  cmpq    $0, (%r8,%rax,8)
    je      2f
    inc     %rax
    and     %r9, %rax
    jmp     1b
2:  mov     %rdx, (%r8,%rax,8)
    ret
END_FUNCTION db_insert

# rax = the entry index (slot - first_slot) of the block of the root at rsi in the Db rdi, or 2^64 - 1. Uses rcx, rdx, rdi, r8-r11, xmm0-xmm2.
LOCAL_FUNCTION db_find
    UNWIND_END_PROLOGUE
    mov     Db_roots(%rdi), %r8
    add     %rdi, %r8
    mov     (Db_roots + 8)(%rdi), %r10      # at most the capacity of probes
    lea     -1(%r10), %r9
    mov     Db_slots(%rdi), %rdx
    add     %rdi, %rdx
    mov     (%rsi), %rcx
    and     %r9, %rcx
1:  test    %r10, %r10
    jz      3f
    mov     (%r8,%rcx,8), %rax
    test    %rax, %rax
    jz      3f
    dec     %rax
    imul    $DbSlot__mem, %rax, %rdi
    add     %rdx, %rdi
    NE32    %rdi, %rsi, 2f
    ret
2:  inc     %rcx
    and     %r9, %rcx
    dec     %r10
    jmp     1b
3:  mov     $-1, %rax
    ret
END_FUNCTION db_find

# The root table of the Db rdi again from its entries: zeroed, then the root of each block; blocks
# their count. rbx db, r12 an entry, r13 its index, r14 the entries in use.
LOCAL_FUNCTION db_rehash
    ENTER 0
    mov     %rdi, %rbx
    mov     Db_roots(%rbx), %rdi
    add     %rbx, %rdi
    mov     (Db_roots + 8)(%rbx), %rsi
    shl     $3, %rsi
    call    lantern_zero
    movq    $0, Db_blocks(%rbx)
    mov     Db_end_slot(%rbx), %r14
    sub     Db_first_slot(%rbx), %r14
    mov     Db_slots(%rbx), %r12
    add     %rbx, %r12
    xor     %r13d, %r13d
1:  cmp     %r14, %r13
    jae     9f
    cmpq    $0, DbSlot_block(%r12)
    je      2f
    mov     %rbx, %rdi
    mov     %r12, %rsi
    lea     1(%r13), %rdx
    call    db_insert
    incq    Db_blocks(%rbx)
2:  add     $DbSlot__mem, %r12
    inc     %r13
    jmp     1b
9:  LEAVE 0
END_FUNCTION db_rehash

# (room, slot, db): no records; first_slot and end_slot the slot. rbx room, rbp the slot, r12 db. Locals: L the size.
FUNCTION lantern_db_init
    ENTER 16
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     %rdx, %r12
    lea     L(%rsp), %rsi
    call    lantern_db_size
    test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax
    cmp     %rax, (%r12)
    jb      8f
    lea     8(%r12), %rdi
    lea     -8(%rax), %rsi
    call    lantern_zero
    mov     %rbp, Db_first_slot(%r12)
    mov     %rbp, Db_end_slot(%r12)
    mov     %r12, %rdi
    mov     %rbx, %rsi
    call    db_layout
    xor     %eax, %eax
9:  LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_db_init

# (db, room, out): the index in out with the capacities of room. rbx db, rbp room, r12 out, r13 the
# entries in use. Locals: L the size.
FUNCTION lantern_db_copy
    ENTER 16
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     %rdx, %r12
    mov     %rbp, %rdi
    lea     L(%rsp), %rsi
    call    lantern_db_size
    test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax
    cmp     %rax, (%r12)
    jb      8f
    mov     Db_end_slot(%rbx), %r13
    sub     Db_first_slot(%rbx), %r13
    cmp     %r13, DbRoom_slots(%rbp)        # room for the entries in use, and the table at most half full
    jb      8f
    mov     Db_blocks(%rbx), %rax
    shl     $1, %rax
    cmp     %rax, DbRoom_roots(%rbp)
    jb      8f
    lea     8(%r12), %rdi
    mov     L(%rsp), %rsi
    sub     $8, %rsi
    call    lantern_zero
    mov     Db_first_slot(%rbx), %rax
    mov     %rax, Db_first_slot(%r12)
    mov     Db_end_slot(%rbx), %rax
    mov     %rax, Db_end_slot(%r12)
    mov     %r12, %rdi
    mov     %rbp, %rsi
    call    db_layout
    mov     Db_slots(%r12), %rdi            # the entries in use, then each root again
    add     %r12, %rdi
    mov     Db_slots(%rbx), %rsi
    add     %rbx, %rsi
    imul    $DbSlot__mem, %r13, %rdx
    call    lantern_copy
    mov     %r12, %rdi
    call    db_rehash
    xor     %eax, %eax
9:  LEAVE 16
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
END_FUNCTION lantern_db_copy

# (db, record, offset): one record at an offset of its segment into the index; nothing changes on a
# status. rbx db, rbp the record, r12 the offset, r13 the entry index, r14 the entry.
FUNCTION lantern_db_add
    ENTER 0
    mov     %rdi, %rbx
    mov     %rsi, %rbp
    mov     (%rdx), %r12
    test    $7, %r12b                       # an offset of a multiple of 8, below 2^48
    jnz     7f
    mov     %r12, %rax
    shr     $48, %rax
    jnz     7f
    mov     $1, %eax                        # length at most DB_RECORD_MAX
    shl     $32, %rax
    cmp     %rax, DbRecord_length(%rbp)
    ja      7f
    mov     DbRecord_slot(%rbp), %r13       # a slot from first_slot, in the room
    sub     Db_first_slot(%rbx), %r13
    jb      7f
    cmp     (Db_slots + 8)(%rbx), %r13
    jae     8f
    imul    $DbSlot__mem, %r13, %r14
    add     Db_slots(%rbx), %r14
    add     %rbx, %r14
    mov     DbRecord_kind(%rbp), %rax
    cmp     $DB_BLOCK, %rax
    je      1f
    cmp     $DB_BLOB_SIDECAR, %rax
    je      4f
    cmp     $DB_COLUMN_SIDECAR, %rax
    jne     7f
4:  cmpq    $0, DbSlot_block(%r14)          # a sidecar: of a slot with a block, an index below DB_SIDECAR_INDICES
    je      7f
    mov     DbRecord_index(%rbp), %r15
    cmp     $DB_SIDECAR_INDICES, %r15
    jae     7f
    mov     DbRecord_length(%rbp), %rcx     # its size: 64 + length rounded up to 8
    add     $(DbRecord__mem + 7), %rcx
    and     $-8, %rcx
    mov     DbSlot_sidecars(%r14), %rax
    test    %rax, %rax
    jz      2f
    cmp     %r12, DbSlot_sidecar_end(%r14)  # after the slot's sidecars, of their size, with a higher index
    jne     7f
    mov     DbSlot_sidecar_end(%r14), %rdx
    sub     %rax, %rdx
    inc     %rdx                            # the bytes of the slot's sidecars
    mov     DbSlot_sidecar_count(%r14), %rax
    imul    %rcx, %rax
    cmp     %rdx, %rax
    jne     7f
    cmp     DbSlot_sidecar_last(%r14), %r15
    jbe     7f
    jmp     3f
2:  lea     1(%r12), %rax
    mov     %rax, DbSlot_sidecars(%r14)
3:  incq    DbSlot_sidecar_count(%r14)
    lea     (%rcx,%r12), %rax
    mov     %rax, DbSlot_sidecar_end(%r14)
    mov     %r15, DbSlot_sidecar_last(%r14)
    bts     %r15, DbSlot_indices(%r14)      # its bit in indices
    jmp     9f
1:  cmpq    $0, DbSlot_block(%r14)          # a block: none in its slot, its root in no other
    jne     7f
    mov     %rbx, %rdi
    lea     DbRecord_root(%rbp), %rsi
    call    db_find
    cmp     $-1, %rax
    jne     7f
    mov     Db_blocks(%rbx), %rax           # the table at most half full
    inc     %rax
    shl     $1, %rax
    cmp     (Db_roots + 8)(%rbx), %rax
    ja      8f
    lea     DbRecord_root(%rbp), %rsi
    COPY32  %r14, %rsi
    lea     1(%r12), %rax
    mov     %rax, DbSlot_block(%r14)
    mov     %rbx, %rdi
    lea     DbRecord_root(%rbp), %rsi
    lea     1(%r13), %rdx
    call    db_insert
    incq    Db_blocks(%rbx)
    mov     DbRecord_slot(%rbp), %rax       # end_slot past it
    inc     %rax
    cmp     Db_end_slot(%rbx), %rax
    jbe     9f
    mov     %rax, Db_end_slot(%rbx)
9:  xor     %eax, %eax
    LEAVE 0
8:  mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 0
7:  mov     $LANTERN_INVALID_RECORD, %eax
    LEAVE 0
END_FUNCTION lantern_db_add

# (db, segment, sidecars, bytes, valid): each whole record of a segment's bytes into the index,
# until one does not fit or is rejected. rbx db, rbp the segment, r12 the sidecars flag, r13 the
# bytes, r14 their count, r15 valid, S7 the position, S8 the segment's first slot, S9 a record.
# Locals: L the record's size, L+8 its offset.
FUNCTION lantern_db_scan
    ENTER 16
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     (%rdx), %r12
    mov     8(%rcx), %r13
    add     %rcx, %r13
    mov     16(%rcx), %r14
    mov     %r8, %r15
    movq    $0, S7(%rsp)
    mov     $DB_SEGMENT_SLOTS, %eax
    mul     %rbp
    jc      9f
    mov     %rax, S8(%rsp)
1:  mov     %r14, %rax                      # its header and its size inside the bytes
    sub     S7(%rsp), %rax
    cmp     $DbRecord__mem, %rax
    jb      9f
    mov     S7(%rsp), %rdx
    lea     (%r13,%rdx), %rdi
    mov     %rdi, S9(%rsp)
    mov     DbRecord_length(%rdi), %rcx
    mov     $1, %edx
    shl     $32, %rdx
    cmp     %rdx, %rcx
    ja      9f
    add     $(DbRecord__mem + 7), %rcx
    and     $-8, %rcx
    cmp     %rax, %rcx
    ja      9f
    mov     %rcx, L(%rsp)
    mov     DbRecord_slot(%rdi), %rax       # a slot of the segment
    sub     S8(%rsp), %rax
    jb      9f
    cmp     $DB_SEGMENT_SLOTS, %rax
    jae     9f
    xor     %eax, %eax                      # a block in a block segment, else a sidecar
    cmpq    $DB_BLOCK, DbRecord_kind(%rdi)
    setne   %al
    cmp     %r12, %rax
    jne     9f
    mov     S7(%rsp), %rax
    mov     %rax, (L + 8)(%rsp)
    mov     %rbx, %rdi
    mov     S9(%rsp), %rsi
    lea     (L + 8)(%rsp), %rdx
    call    lantern_db_add
    cmp     $LANTERN_BUFFER_TOO_SMALL, %rax
    je      8f
    test    %rax, %rax
    jnz     9f
    mov     L(%rsp), %rax
    add     %rax, S7(%rsp)
    jmp     1b
8:  mov     S7(%rsp), %rax
    mov     %rax, (%r15)
    mov     $LANTERN_BUFFER_TOO_SMALL, %eax
    LEAVE 16
9:  mov     S7(%rsp), %rax
    mov     %rax, (%r15)
    xor     %eax, %eax
    LEAVE 16
END_FUNCTION lantern_db_scan

# (db, root, slot): the slot of the root's block, or 2^64 - 1. Locals: 0 db, 8 slot.
FUNCTION lantern_db_find_root
    FRAME 16
    mov     %rdi, (%rsp)
    mov     %rdx, 8(%rsp)
    call    db_find
    cmp     $-1, %rax
    je      1f
    mov     (%rsp), %rcx
    add     Db_first_slot(%rcx), %rax
1:  mov     8(%rsp), %rcx
    mov     %rax, (%rcx)
    xor     %eax, %eax
    UNFRAME 16
END_FUNCTION lantern_db_find_root

# (db, slot): first_slot the slot, at most end_slot; the kept entries to the front, the root table
# again. A slot not after first_slot changes nothing. rbx db, rbp the new first slot, r12 first_slot,
# r13 end_slot, r14 the entries dropped, r15 those kept, S7 the entries.
FUNCTION lantern_db_prune
    ENTER 0
    mov     %rdi, %rbx
    mov     (%rsi), %rbp
    mov     Db_first_slot(%rbx), %r12
    mov     Db_end_slot(%rbx), %r13
    cmp     %r12, %rbp
    jbe     9f
    cmp     %r13, %rbp
    cmova   %r13, %rbp
    mov     %rbp, %r14
    sub     %r12, %r14
    mov     %r13, %r15
    sub     %rbp, %r15
    mov     Db_slots(%rbx), %rax
    add     %rbx, %rax
    mov     %rax, S7(%rsp)
    mov     %rax, %rdi
    imul    $DbSlot__mem, %r14, %rsi
    add     %rax, %rsi
    imul    $DbSlot__mem, %r15, %rdx
    call    lantern_copy
    imul    $DbSlot__mem, %r15, %rdi
    add     S7(%rsp), %rdi
    imul    $DbSlot__mem, %r14, %rsi
    call    lantern_zero
    mov     %rbp, Db_first_slot(%rbx)
    mov     %rbx, %rdi
    call    db_rehash
9:  xor     %eax, %eax
    LEAVE 0
END_FUNCTION lantern_db_prune
