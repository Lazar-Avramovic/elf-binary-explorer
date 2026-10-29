BITS 64
default rel
%include "bx.inc"

%define NAME_MIN 22
%define NAME_MAX 40
%define TYPE_W 15
%define FLAGS_W 14
%define NUM_W 16

extern open_and_map
extern check_elf
extern parse_sections
extern file_map
extern sec_off
extern sec_num
extern shstr_off
extern shstr_size
extern out_write
extern out_cstr
extern out_char
extern out_hex
extern out_dec
extern out_pad
extern strlen
extern safe_strlen

global cmd_sections

section .bss
alignb 8
name_width: resq 1
index_width: resq 1

section .rodata
h_idx: db "[Nr]", 0
h_name: db "Name", 0
h_type: db "Type", 0
h_flags: db "Flags", 0
h_addr: db "Address", 0
h_off: db "Offset", 0
h_size: db "Size", 0

lbracket: db "[", 0
rbracket: db "] ", 0
dots: db "..", 0
hex_prefix: db "0x", 0
name_none: db "<none>", 0
name_bad: db "<bad>", 0
msg_no_sections: db "No section table.", 0
nl: db 10, 0

st_null: db "NULL", 0
st_progbits: db "PROGBITS", 0
st_symtab: db "SYMTAB", 0
st_strtab: db "STRTAB", 0
st_rela: db "RELA", 0
st_hash: db "HASH", 0
st_dynamic: db "DYNAMIC", 0
st_note: db "NOTE", 0
st_nobits: db "NOBITS", 0
st_rel: db "REL", 0
st_shlib: db "SHLIB", 0
st_dynsym: db "DYNSYM", 0
st_init_array: db "INIT_ARRAY", 0
st_fini_array: db "FINI_ARRAY", 0
st_preinit_array: db "PREINIT_ARRAY", 0
st_group: db "GROUP", 0
st_symtab_shndx: db "SYMTAB_SHNDX", 0
st_relr: db "RELR", 0
st_gnu_hash: db "GNU_HASH", 0
st_verdef: db "VERDEF", 0
st_verneed: db "VERNEED", 0
st_versym: db "VERSYM", 0

section .text

global cmd_sections
; rdi = path
cmd_sections:
    push r12
    push r13
    push r14
    push r15
    call open_and_map
    call check_elf
    call parse_sections

    cmp qword [rel sec_num], 0
    je .no_sections

    call compute_index_width
    call compute_name_width
    call print_sections_header

    xor r12d, r12d
.loop:
    cmp r12, [rel sec_num]
    jae .done

    mov rax, [rel file_map]
    add rax, [rel sec_off]
    mov rcx, r12
    shl rcx, 6
    add rax, rcx
    mov r13, rax

    mov rdi, r12
    call print_index

    mov rax, [rel shstr_size]
    test rax, rax
    jz .name_none
    mov edi, [r13]
    cmp rdi, rax
    jae .name_bad
    mov r14, [rel file_map]
    add r14, [rel shstr_off]
    add r14, rdi
    sub rax, rdi
    mov rdi, r14
    mov rsi, rax
    call safe_strlen
    mov rdi, r14
    mov rsi, rax
    call print_name_sanitized
    jmp .name_done
.name_none:
    lea rdi, [rel name_none]
    mov esi, 6
    call print_name_sanitized
    jmp .name_done
.name_bad:
    lea rdi, [rel name_bad]
    mov esi, 5
    call print_name_sanitized
.name_done:
    mov rdi, 2
    call out_pad

    mov edi, [r13 + 4]
    call sh_type_name
    test rax, rax
    jz .type_unknown
    mov r14, rax
    mov rdi, rax
    call strlen
    mov r15, rax
    mov rdi, r14
    mov rsi, r15
    call out_write
    cmp r15, TYPE_W
    jae .type_done
    mov rdi, TYPE_W
    sub rdi, r15
    call out_pad
    jmp .type_done
.type_unknown:
    lea rdi, [rel hex_prefix]
    call out_cstr
    mov edi, [r13 + 4]
    mov esi, 8
    call out_hex
    mov rdi, TYPE_W - 10
    call out_pad
.type_done:
    mov rdi, 2
    call out_pad

    mov rdi, [r13 + 8]
    call print_sh_flags
    mov rdi, 2
    call out_pad

    mov rdi, [r13 + 16]
    mov esi, NUM_W
    call out_hex
    mov rdi, 2
    call out_pad

    mov rdi, [r13 + 24]
    mov esi, NUM_W
    call out_hex
    mov rdi, 2
    call out_pad

    mov rdi, [r13 + 32]
    mov esi, NUM_W
    call out_hex
    lea rdi, [rel nl]
    call out_cstr

    inc r12
    jmp .loop

.done:
    jmp .exit
.no_sections:
    lea rdi, [rel msg_no_sections]
    call out_cstr
    lea rdi, [rel nl]
    call out_cstr
.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

compute_index_width:
    mov r15, 3
    mov rax, [rel sec_num]
    cmp rax, 1000
    jbe .store
    mov r15, 4
    cmp rax, 10000
    jbe .store
    mov r15, 5
    cmp rax, 100000
    jbe .store
    mov r15, 6
    cmp rax, 1000000
    jbe .store
    mov r15, 7
.store:
    mov [rel index_width], r15
    ret

compute_name_width:
    mov r15, NAME_MIN
    mov r14, [rel shstr_size]
    test r14, r14
    jz .done
    xor r12d, r12d
.loop:
    cmp r12, [rel sec_num]
    jae .done
    mov r13, [rel file_map]
    add r13, [rel sec_off]
    mov rax, r12
    shl rax, 6
    add r13, rax
    mov edi, [r13]
    cmp rdi, r14
    jae .next
    mov rsi, [rel file_map]
    add rsi, [rel shstr_off]
    add rsi, rdi
    mov rax, r14
    sub rax, rdi
    mov rdi, rsi
    mov rsi, rax
    call safe_strlen
    cmp rax, r15
    jbe .next
    cmp rax, NAME_MAX
    jbe .take
    mov rax, NAME_MAX
.take:
    mov r15, rax
.next:
    inc r12
    jmp .loop
.done:
    mov [rel name_width], r15
    ret

print_index:
    ; rdi = section index; prints "[" + right-aligned index + "] "
    push r12
    push r13
    mov r12, rdi
    mov rax, r12
    mov r13, 1
    mov ecx, 10
.digits:
    cmp rax, 10
    jb .ready
    xor edx, edx
    div rcx
    inc r13
    jmp .digits
.ready:
    lea rdi, [rel lbracket]
    call out_cstr
    mov rdi, [rel index_width]
    cmp rdi, r13
    jae .pad
    mov rdi, r13
.pad:
    sub rdi, r13
    call out_pad
    mov rdi, r12
    call out_dec
    lea rdi, [rel rbracket]
    call out_cstr
    pop r13
    pop r12
    ret

print_sections_header:
    lea rdi, [rel h_idx]
    call out_cstr
    mov rdi, [rel index_width]
    dec rdi
    call out_pad
    lea rdi, [rel h_name]
    call out_cstr
    mov rdi, [rel name_width]
    sub rdi, 4
    call out_pad
    mov rdi, 2
    call out_pad
    lea rdi, [rel h_type]
    call out_cstr
    mov rdi, TYPE_W - 4
    call out_pad
    mov rdi, 2
    call out_pad
    lea rdi, [rel h_flags]
    call out_cstr
    mov rdi, FLAGS_W - 5
    call out_pad
    mov rdi, 2
    call out_pad
    lea rdi, [rel h_addr]
    call out_cstr
    mov rdi, NUM_W - 7
    call out_pad
    mov rdi, 2
    call out_pad
    lea rdi, [rel h_off]
    call out_cstr
    mov rdi, NUM_W - 6
    call out_pad
    mov rdi, 2
    call out_pad
    lea rdi, [rel h_size]
    call out_cstr
    lea rdi, [rel nl]
    call out_cstr
    ret

print_name_sanitized:
    ; rdi = bytes, rsi = length; prints exactly name_width columns
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov rax, [rel name_width]
    mov r15, r13
    cmp r15, rax
    jbe .have_len
    mov r15, rax
    sub r15, 2
.have_len:
    xor r14d, r14d
.loop:
    cmp r14, r15
    jae .after
    movzx eax, byte [r12 + r14]
    cmp al, 0x20
    jb .dot
    cmp al, 0x7e
    ja .dot
    jmp .emit
.dot:
    mov al, '.'
.emit:
    mov edi, eax
    call out_char
    inc r14
    jmp .loop
.after:
    mov rax, [rel name_width]
    cmp r13, rax
    jbe .pad
    lea rdi, [rel dots]
    call out_cstr
    jmp .restore
.pad:
    mov rdi, [rel name_width]
    sub rdi, r13
    call out_pad
.restore:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

sh_type_name:
    ; edi = sh_type, rax = name or 0
    cmp edi, 0
    jne .t1
    lea rax, [rel st_null]
    ret
.t1:
    cmp edi, 1
    jne .t2
    lea rax, [rel st_progbits]
    ret
.t2:
    cmp edi, 2
    jne .t3
    lea rax, [rel st_symtab]
    ret
.t3:
    cmp edi, 3
    jne .t4
    lea rax, [rel st_strtab]
    ret
.t4:
    cmp edi, 4
    jne .t5
    lea rax, [rel st_rela]
    ret
.t5:
    cmp edi, 5
    jne .t6
    lea rax, [rel st_hash]
    ret
.t6:
    cmp edi, 6
    jne .t7
    lea rax, [rel st_dynamic]
    ret
.t7:
    cmp edi, 7
    jne .t8
    lea rax, [rel st_note]
    ret
.t8:
    cmp edi, 8
    jne .t9
    lea rax, [rel st_nobits]
    ret
.t9:
    cmp edi, 9
    jne .t10
    lea rax, [rel st_rel]
    ret
.t10:
    cmp edi, 10
    jne .t11
    lea rax, [rel st_shlib]
    ret
.t11:
    cmp edi, 11
    jne .t14
    lea rax, [rel st_dynsym]
    ret
.t14:
    cmp edi, 14
    jne .t15
    lea rax, [rel st_init_array]
    ret
.t15:
    cmp edi, 15
    jne .t16
    lea rax, [rel st_fini_array]
    ret
.t16:
    cmp edi, 16
    jne .t17
    lea rax, [rel st_preinit_array]
    ret
.t17:
    cmp edi, 17
    jne .t18
    lea rax, [rel st_group]
    ret
.t18:
    cmp edi, 18
    jne .t19
    lea rax, [rel st_symtab_shndx]
    ret
.t19:
    cmp edi, 19
    jne .t_gnu_hash
    lea rax, [rel st_relr]
    ret
.t_gnu_hash:
    cmp edi, 0x6ffffff6
    jne .t_verdef
    lea rax, [rel st_gnu_hash]
    ret
.t_verdef:
    cmp edi, 0x6ffffffd
    jne .t_verneed
    lea rax, [rel st_verdef]
    ret
.t_verneed:
    cmp edi, 0x6ffffffe
    jne .t_versym
    lea rax, [rel st_verneed]
    ret
.t_versym:
    cmp edi, 0x6fffffff
    jne .unknown
    lea rax, [rel st_versym]
    ret
.unknown:
    xor eax, eax
    ret

print_sh_flags:
    ; rdi = sh_flags; prints exactly FLAGS_W columns
    push r12
    sub rsp, 32
    lea r8, [rsp]
    xor ecx, ecx
    test rdi, 0x1
    jz .w
    mov byte [r8 + rcx], 'W'
    inc ecx
.w:
    test rdi, 0x2
    jz .a
    mov byte [r8 + rcx], 'A'
    inc ecx
.a:
    test rdi, 0x4
    jz .x
    mov byte [r8 + rcx], 'X'
    inc ecx
.x:
    test rdi, 0x10
    jz .m
    mov byte [r8 + rcx], 'M'
    inc ecx
.m:
    test rdi, 0x20
    jz .s
    mov byte [r8 + rcx], 'S'
    inc ecx
.s:
    test rdi, 0x40
    jz .i
    mov byte [r8 + rcx], 'I'
    inc ecx
.i:
    test rdi, 0x80
    jz .l
    mov byte [r8 + rcx], 'L'
    inc ecx
.l:
    test rdi, 0x100
    jz .o
    mov byte [r8 + rcx], 'O'
    inc ecx
.o:
    test rdi, 0x200
    jz .g
    mov byte [r8 + rcx], 'G'
    inc ecx
.g:
    test rdi, 0x400
    jz .t
    mov byte [r8 + rcx], 'T'
    inc ecx
.t:
    test rdi, 0x800
    jz .c
    mov byte [r8 + rcx], 'C'
    inc ecx
.c:
    test rdi, 0x200000
    jz .r
    mov byte [r8 + rcx], 'R'
    inc ecx
.r:
    bt rdi, 31
    jnc .e
    mov byte [r8 + rcx], 'E'
    inc ecx
.e:
    mov rax, rdi
    mov edx, 0x80200FF7
    and rax, rdx
    cmp rax, rdi
    je .known
    mov byte [r8 + rcx], '?'
    inc ecx
.known:
    test ecx, ecx
    jnz .has
    mov byte [r8], '-'
    mov ecx, 1
.has:
    mov byte [r8 + rcx], 0
    mov r12, rcx
    mov rdi, r8
    mov rsi, r12
    call out_write
    cmp r12, FLAGS_W
    jae .done
    mov rdi, FLAGS_W
    sub rdi, r12
    call out_pad
.done:
    add rsp, 32
    pop r12
    ret
