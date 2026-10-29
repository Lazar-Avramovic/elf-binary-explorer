BITS 64
default rel
%include "bx.inc"

extern out_write
extern out_flush
extern err_write
extern err_cstr
extern streq
extern cmd_info
extern cmd_sections
extern cmd_hex
extern out_error

section .rodata
version_text: db "bx 0.1.0", 10
version_len equ $ - version_text

usage_text:
    db "bx 0.1.0 - a tiny binary explorer", 10, 10
    db "Usage:", 10
    db "  bx info <file>             show ELF header summary", 10
    db "  bx sections <file>         list ELF sections", 10
    db "  bx hex [options] <file>    hex dump a file", 10
    db "  bx help                    show this help", 10
    db "  bx version                 show version", 10, 10
    db "Hex options:", 10
    db "  -o, --offset <n>           start offset (decimal or 0x hex)", 10
    db "  -n, --length <n>           number of bytes to dump", 10, 10
    db "Supported: ELF64, little-endian, x86-64 Linux.", 10
usage_len equ $ - usage_text

cmd_help: db "help", 0
cmd_version: db "version", 0
cmd_h: db "-h", 0
cmd_help_long: db "--help", 0
cmd_V: db "-V", 0
cmd_version_long: db "--version", 0
cmd_info_s: db "info", 0
cmd_sections_s: db "sections", 0
cmd_hex_s: db "hex", 0
dashdash: db "--", 0

msg_unknown: db "unknown command", 0
msg_no_command: db "no command given", 0
msg_info_usage: db "usage: bx info <file>", 0
msg_sections_usage: db "usage: bx sections <file>", 0
prefix: db "bx: ", 0
newline: db 10, 0

section .text
global _start

_start:
    cld
    mov r12, [rsp]
    lea r13, [rsp + 8]

    cmp r12, 1
    jle .no_args

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_help]
    call streq
    test eax, eax
    jnz .help

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_h]
    call streq
    test eax, eax
    jnz .help

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_help_long]
    call streq
    test eax, eax
    jnz .help

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_version]
    call streq
    test eax, eax
    jnz .version

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_V]
    call streq
    test eax, eax
    jnz .version

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_version_long]
    call streq
    test eax, eax
    jnz .version

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_info_s]
    call streq
    test eax, eax
    jnz .info

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_sections_s]
    call streq
    test eax, eax
    jnz .sections

    mov rdi, [r13 + 8]
    lea rsi, [rel cmd_hex_s]
    call streq
    test eax, eax
    jnz .hex

    lea rdi, [rel msg_unknown]
    jmp usage_error

.no_args:
    lea rdi, [rel msg_no_command]
    jmp usage_error

.info:
    cmp r12, 3
    je .info_one
    cmp r12, 4
    jne .info_usage
    mov rdi, [r13 + 16]
    lea rsi, [rel dashdash]
    call streq
    test eax, eax
    jz .info_trailing
    mov rdi, [r13 + 24]
    call cmd_info
    jmp .exit_ok
.info_trailing:
    mov rdi, [r13 + 24]
    lea rsi, [rel dashdash]
    call streq
    test eax, eax
    jz .info_usage
    mov rdi, [r13 + 16]
    call cmd_info
    jmp .exit_ok
.info_one:
    mov rdi, [r13 + 16]
    call cmd_info
    jmp .exit_ok
.info_usage:
    lea rdi, [rel msg_info_usage]
    jmp usage_error

.sections:
    cmp r12, 3
    je .sections_one
    cmp r12, 4
    jne .sections_usage
    mov rdi, [r13 + 16]
    lea rsi, [rel dashdash]
    call streq
    test eax, eax
    jz .sections_trailing
    mov rdi, [r13 + 24]
    call cmd_sections
    jmp .exit_ok
.sections_trailing:
    mov rdi, [r13 + 24]
    lea rsi, [rel dashdash]
    call streq
    test eax, eax
    jz .sections_usage
    mov rdi, [r13 + 16]
    call cmd_sections
    jmp .exit_ok
.sections_one:
    mov rdi, [r13 + 16]
    call cmd_sections
    jmp .exit_ok
.sections_usage:
    lea rdi, [rel msg_sections_usage]
    jmp usage_error

.hex:
    mov rdi, r12
    sub rdi, 2
    lea rsi, [r13 + 16]
    call cmd_hex
    jmp .exit_ok

.help:
    lea rdi, [rel usage_text]
    mov rsi, usage_len
    call out_write
    jmp .exit_ok

.version:
    lea rdi, [rel version_text]
    mov rsi, version_len
    call out_write
    jmp .exit_ok

.exit_ok:
    call out_flush
    cmp qword [rel out_error], 0
    jne .exit_fail
    mov eax, SYS_EXIT
    xor edi, edi
    syscall
.exit_fail:
    mov eax, SYS_EXIT
    mov edi, 1
    syscall

global usage_error
usage_error:
    ; rdi = message
    push rdi
    call out_flush
    lea rdi, [rel prefix]
    call err_cstr
    pop rdi
    call err_cstr
    lea rdi, [rel newline]
    call err_cstr
    lea rdi, [rel usage_text]
    mov rsi, usage_len
    call err_write
    mov eax, SYS_EXIT
    mov edi, 2
    syscall
