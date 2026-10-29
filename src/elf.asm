BITS 64
default rel
%include "bx.inc"

extern out_cstr
extern out_hex
extern out_dec
extern out_flush
extern err_cstr
extern strlen

global open_and_map
global check_elf
global parse_sections
global cmd_info

global file_map
global file_size
global sec_off
global sec_num
global shstr_off
global shstr_size

section .bss
alignb 8
file_map: resq 1
file_size: resq 1
cur_path: resq 1
stat_buf: resb STAT_BUF_SIZE
probe_buf: resb 1
sec_off: resq 1
sec_num: resq 1
shstr_off: resq 1
shstr_size: resq 1
ph_off: resq 1
ph_num: resq 1

section .rodata
f_prefix: db "bx: ", 0
f_colon: db ": ", 0
f_nl: db 10, 0

msg_open: db "cannot open file", 0
msg_stat: db "cannot stat file", 0
msg_dir: db "is a directory", 0
msg_not_reg: db "not a regular file", 0
msg_unreported: db "file size is not reported (unsupported)", 0
msg_read: db "cannot read file", 0
msg_map: db "cannot map file", 0
msg_not_elf: db "not an ELF file", 0
msg_not_64: db "only 64-bit ELF is supported", 0
msg_not_le: db "only little-endian ELF is supported", 0
msg_bad_ver: db "unsupported ELF version", 0
msg_bad_ehdr: db "malformed ELF header", 0
msg_bad_sections: db "malformed section table", 0
msg_bad_shstr: db "malformed section name table", 0
msg_bad_phdrs: db "malformed program header table", 0

l_file: db "File:      ", 0
l_size: db "Size:      ", 0
l_format: db "Format:    ELF64 little-endian", 0
l_type: db "Type:      ", 0
l_machine: db "Machine:   ", 0
l_entry: db "Entry:     0x", 0
l_sections: db "Sections:  ", 0
l_segments: db "Segments:  ", 0
s_bytes: db " bytes", 0
s_open: db " (", 0
s_close: db ")", 0
nl: db 10, 0

type_none: db "NONE", 0
type_rel: db "REL", 0
type_exec: db "EXEC", 0
type_dyn: db "DYN", 0
type_core: db "CORE", 0
type_unknown: db "UNKNOWN", 0

machine_386: db "x86", 0
machine_arm: db "ARM", 0
machine_x86_64: db "x86-64", 0
machine_aarch64: db "AArch64", 0
machine_riscv: db "RISC-V", 0
machine_unknown: db "UNKNOWN", 0

section .text

fail:
    ; rdi = message
    push rdi
    call out_flush
    lea rdi, [rel f_prefix]
    call err_cstr
    mov rdi, [rel cur_path]
    call err_cstr
    lea rdi, [rel f_colon]
    call err_cstr
    pop rdi
    call err_cstr
    lea rdi, [rel f_nl]
    call err_cstr
    mov eax, SYS_EXIT
    mov edi, 1
    syscall

global open_and_map
; rdi = path; returns rax = map, rdx = size; exits on failure
open_and_map:
    push r12
    push r13
    mov r12, rdi
    mov [rel cur_path], rdi

    mov rsi, O_RDONLY | O_NONBLOCK
    xor edx, edx
    mov eax, SYS_OPEN
    syscall
    cmp rax, -4096
    jae .open_err
    mov r13, rax

    mov rdi, r13
    lea rsi, [rel stat_buf]
    mov eax, SYS_FSTAT
    syscall
    cmp rax, -4096
    jae .stat_err

    mov eax, [rel stat_buf + 24]
    and eax, 0xF000
    cmp eax, 0x4000
    je .dir_err
    cmp eax, 0x8000
    jne .not_reg

    mov rdx, [rel stat_buf + 48]
    mov [rel file_size], rdx
    test rdx, rdx
    jz .zero_probe

    xor edi, edi
    mov rsi, rdx
    mov edx, PROT_READ
    mov r10, MAP_PRIVATE
    mov r8, r13
    xor r9d, r9d
    mov eax, SYS_MMAP
    syscall
    cmp rax, -4096
    jae .map_err
    mov [rel file_map], rax

    mov rdi, r13
    mov eax, SYS_CLOSE
    syscall
    mov rax, [rel file_map]
    mov rdx, [rel file_size]
    pop r13
    pop r12
    ret

.zero_probe:
    mov rdi, r13
    lea rsi, [rel probe_buf]
    mov edx, 1
    mov eax, SYS_READ
    syscall
    cmp rax, -4
    je .zero_probe
    test rax, rax
    jg .unreported_size
    js .read_err

.empty:
    mov qword [rel file_map], 0
    mov rdi, r13
    mov eax, SYS_CLOSE
    syscall
    xor eax, eax
    xor edx, edx
    pop r13
    pop r12
    ret

.open_err:
    lea rdi, [rel msg_open]
    jmp fail
.stat_err:
    lea rdi, [rel msg_stat]
    jmp fail
.dir_err:
    lea rdi, [rel msg_dir]
    jmp fail
.not_reg:
    lea rdi, [rel msg_not_reg]
    jmp fail
.unreported_size:
    lea rdi, [rel msg_unreported]
    jmp fail
.read_err:
    lea rdi, [rel msg_read]
    jmp fail
.map_err:
    lea rdi, [rel msg_map]
    jmp fail

global check_elf
check_elf:
    mov rdi, [rel file_map]
    mov rsi, [rel file_size]
    cmp rsi, ELF64_EHDR_SIZE
    jb .not_elf
    cmp byte [rdi], 0x7f
    jne .not_elf
    cmp byte [rdi + 1], 'E'
    jne .not_elf
    cmp byte [rdi + 2], 'L'
    jne .not_elf
    cmp byte [rdi + 3], 'F'
    jne .not_elf
    cmp byte [rdi + 4], 2
    jne .not_64
    cmp byte [rdi + 5], 1
    jne .not_le
    mov eax, [rdi + 20]
    cmp eax, 1
    jne .bad_version
    movzx eax, word [rdi + 52]
    cmp eax, ELF64_EHDR_SIZE
    jb .bad_header
    ret
.not_elf:
    lea rdi, [rel msg_not_elf]
    jmp fail
.not_64:
    lea rdi, [rel msg_not_64]
    jmp fail
.not_le:
    lea rdi, [rel msg_not_le]
    jmp fail
.bad_version:
    lea rdi, [rel msg_bad_ver]
    jmp fail
.bad_header:
    lea rdi, [rel msg_bad_ehdr]
    jmp fail

global parse_sections
parse_sections:
    mov rdi, [rel file_map]
    mov rsi, [rel file_size]

    mov rax, [rdi + 40]
    mov [rel sec_off], rax
    movzx ecx, word [rdi + 60]
    movzx edx, word [rdi + 58]
    movzx r8d, word [rdi + 62]

    test rax, rax
    jnz .has_table
    test ecx, ecx
    jnz .bad
    mov qword [rel sec_num], 0
    mov qword [rel shstr_off], 0
    mov qword [rel shstr_size], 0
    ret

.has_table:
    mov r9, rsi
    sub r9, ELF64_EHDR_SIZE
    cmp rax, r9
    ja .bad
    cmp edx, ELF64_SHDR_SIZE
    jne .bad

    mov r10, rcx
    test r10, r10
    jnz .count_ready
    mov r10, [rdi + rax + 32]
    cmp r10, 0x100000
    ja .bad
    test r10, r10
    jz .no_sections
.count_ready:
    mov r11, r10
    shl r11, 6
    add r11, rax
    jc .bad
    cmp r11, rsi
    ja .bad
    mov [rel sec_num], r10

    test r8d, r8d
    jz .no_names
    cmp r8d, 0xffff
    jne .idx_ready
    mov r8d, [rdi + rax + 40]
.idx_ready:
    cmp r8, r10
    jae .bad_shstr

    mov r9, r8
    shl r9, 6
    add r9, rax
    add r9, rdi
    mov r11, [r9 + 24]
    mov r10, [r9 + 32]
    mov r9, rsi
    sub r9, r11
    jc .bad_shstr
    cmp r10, r9
    ja .bad_shstr
    mov [rel shstr_off], r11
    mov [rel shstr_size], r10
    ret

.no_names:
    mov qword [rel shstr_off], 0
    mov qword [rel shstr_size], 0
    ret
.no_sections:
    mov qword [rel sec_num], 0
    mov qword [rel shstr_off], 0
    mov qword [rel shstr_size], 0
    ret
.bad:
    lea rdi, [rel msg_bad_sections]
    jmp fail
.bad_shstr:
    lea rdi, [rel msg_bad_shstr]
    jmp fail

parse_phdrs:
    mov rdi, [rel file_map]
    mov rsi, [rel file_size]
    mov rax, [rdi + 32]
    mov [rel ph_off], rax
    movzx ecx, word [rdi + 56]
    movzx edx, word [rdi + 54]

    test rax, rax
    jnz .has_table
    test ecx, ecx
    jnz .bad
    mov qword [rel ph_num], 0
    ret

.has_table:
    cmp edx, ELF64_PHDR_SIZE
    jne .bad
    mov r8, rcx
    cmp r8, 0xffff
    jne .count_ready
    mov r9, [rel sec_off]
    test r9, r9
    jz .bad
    add r9, rdi
    mov r8d, [r9 + 44]
    cmp r8, 0x100000
    ja .bad
.count_ready:
    mov r9, r8
    imul r9, ELF64_PHDR_SIZE
    jo .bad
    add r9, rax
    jc .bad
    cmp r9, rsi
    ja .bad
    mov [rel ph_num], r8
    ret
.bad:
    lea rdi, [rel msg_bad_phdrs]
    jmp fail

elf_type_name:
    cmp edi, 0
    jne .t1
    lea rax, [rel type_none]
    ret
.t1:
    cmp edi, 1
    jne .t2
    lea rax, [rel type_rel]
    ret
.t2:
    cmp edi, 2
    jne .t3
    lea rax, [rel type_exec]
    ret
.t3:
    cmp edi, 3
    jne .t4
    lea rax, [rel type_dyn]
    ret
.t4:
    cmp edi, 4
    jne .tunknown
    lea rax, [rel type_core]
    ret
.tunknown:
    lea rax, [rel type_unknown]
    ret

machine_name:
    cmp edi, 3
    jne .m1
    lea rax, [rel machine_386]
    ret
.m1:
    cmp edi, 40
    jne .m2
    lea rax, [rel machine_arm]
    ret
.m2:
    cmp edi, 62
    jne .m3
    lea rax, [rel machine_x86_64]
    ret
.m3:
    cmp edi, 183
    jne .m4
    lea rax, [rel machine_aarch64]
    ret
.m4:
    cmp edi, 243
    jne .munknown
    lea rax, [rel machine_riscv]
    ret
.munknown:
    lea rax, [rel machine_unknown]
    ret

global cmd_info
; rdi = path
cmd_info:
    call open_and_map
    call check_elf
    call parse_sections
    call parse_phdrs

    lea rdi, [rel l_file]
    call out_cstr
    mov rdi, [rel cur_path]
    call out_cstr
    lea rdi, [rel nl]
    call out_cstr

    lea rdi, [rel l_size]
    call out_cstr
    mov rdi, [rel file_size]
    call out_dec
    lea rdi, [rel s_bytes]
    call out_cstr
    lea rdi, [rel nl]
    call out_cstr

    lea rdi, [rel l_format]
    call out_cstr
    lea rdi, [rel nl]
    call out_cstr

    lea rdi, [rel l_type]
    call out_cstr
    mov rdi, [rel file_map]
    movzx edi, word [rdi + 16]
    call elf_type_name
    mov rdi, rax
    call out_cstr
    lea rdi, [rel s_open]
    call out_cstr
    mov rdi, [rel file_map]
    movzx edi, word [rdi + 16]
    call out_dec
    lea rdi, [rel s_close]
    call out_cstr
    lea rdi, [rel nl]
    call out_cstr

    lea rdi, [rel l_machine]
    call out_cstr
    mov rdi, [rel file_map]
    movzx edi, word [rdi + 18]
    call machine_name
    mov rdi, rax
    call out_cstr
    lea rdi, [rel s_open]
    call out_cstr
    mov rdi, [rel file_map]
    movzx edi, word [rdi + 18]
    call out_dec
    lea rdi, [rel s_close]
    call out_cstr
    lea rdi, [rel nl]
    call out_cstr

    lea rdi, [rel l_entry]
    call out_cstr
    mov rdi, [rel file_map]
    mov rdi, [rdi + 24]
    mov esi, 16
    call out_hex
    lea rdi, [rel nl]
    call out_cstr

    lea rdi, [rel l_sections]
    call out_cstr
    mov rdi, [rel sec_num]
    call out_dec
    lea rdi, [rel nl]
    call out_cstr

    lea rdi, [rel l_segments]
    call out_cstr
    mov rdi, [rel ph_num]
    call out_dec
    lea rdi, [rel nl]
    call out_cstr
    ret
