BITS 64
default rel
%include "bx.inc"

extern strlen

section .bss
alignb 8
global out_error
out_error: resq 1
out_len: resq 1
out_buf: resb OUT_BUF_SIZE

section .rodata
hex_digits: db "0123456789abcdef"
err_prefix: db "bx: ", 0
newline: db 10, 0

section .text

global out_flush
out_flush:
    mov r8, [rel out_len]
    test r8, r8
    jz .done
    lea rsi, [rel out_buf]
.again:
    mov edi, 1
    mov rdx, r8
    mov eax, SYS_WRITE
    syscall
    cmp rax, -4
    je .again
    test rax, rax
    jg .progress
    mov qword [rel out_error], 1
    jmp .reset
.progress:
    add rsi, rax
    sub r8, rax
    jnz .again
.reset:
    mov qword [rel out_len], 0
.done:
    ret

global out_write
; rdi = buffer, rsi = length
out_write:
    test rsi, rsi
    jz .ret
    cmp rsi, OUT_BUF_SIZE
    jae .direct
    mov rax, [rel out_len]
    lea rdx, [rax + rsi]
    cmp rdx, OUT_BUF_SIZE
    jbe .copy
    push rdi
    push rsi
    call out_flush
    pop rsi
    pop rdi
.copy:
    mov r8, rsi
    mov rcx, rsi
    mov rsi, rdi
    lea rdi, [rel out_buf]
    add rdi, [rel out_len]
    cld
    rep movsb
    add [rel out_len], r8
.ret:
    ret
.direct:
    cmp qword [rel out_len], 0
    je .direct_go
    push rdi
    push rsi
    call out_flush
    pop rsi
    pop rdi
.direct_go:
    mov r8, rdi
    mov r9, rsi
.loop:
    test r9, r9
    jz .ret
    mov edi, 1
    mov rsi, r8
    mov rdx, r9
    mov eax, SYS_WRITE
    syscall
    cmp rax, -4
    je .loop
    test rax, rax
    jg .direct_progress
    mov qword [rel out_error], 1
    ret
.direct_progress:
    add r8, rax
    sub r9, rax
    jmp .loop

global out_char
; dil = byte
out_char:
    sub rsp, 16
    mov [rsp], dil
    mov rdi, rsp
    mov esi, 1
    call out_write
    add rsp, 16
    ret

global out_cstr
; rdi = NUL-terminated string
out_cstr:
    push rdi
    call strlen
    mov rsi, rax
    pop rdi
    call out_write
    ret

global out_hex
; rdi = value, rsi = digits (clamped to 1..16)
out_hex:
    push r12
    push r13
    sub rsp, 32
    mov r12, rsi
    cmp r12, 16
    jbe .digits_ok
    mov r12, 16
.digits_ok:
    test r12, r12
    jnz .loop
    mov r12, 1
.loop:
    lea r13, [rsp]
    lea r11, [rel hex_digits]
    xor r9d, r9d
.digit:
    mov rdx, rdi
    mov r10, r12
    dec r10
    sub r10, r9
    shl r10, 2
    mov ecx, r10d
    shr rdx, cl
    and edx, 0xf
    mov dl, [r11 + rdx]
    mov [r13 + r9], dl
    inc r9
    cmp r9, r12
    jb .digit
    mov rdi, r13
    mov rsi, r12
    call out_write
    add rsp, 32
    pop r13
    pop r12
    ret

global out_dec
; rdi = unsigned value
out_dec:
    push r12
    sub rsp, 32
    lea r12, [rsp + 31]
    mov rax, rdi
    xor ecx, ecx
    mov r8, 10
.loop:
    xor edx, edx
    div r8
    add dl, '0'
    dec r12
    mov [r12], dl
    inc rcx
    test rax, rax
    jnz .loop
    mov rdi, r12
    mov rsi, rcx
    call out_write
    add rsp, 32
    pop r12
    ret

global out_pad
; rdi = space count
out_pad:
    push r12
    mov r12, rdi
    cmp r12, 4096
    jbe .loop
    mov r12, 4096
.loop:
    test r12, r12
    jz .done
    mov edi, ' '
    call out_char
    dec r12
    jmp .loop
.done:
    pop r12
    ret

global err_write
; rdi = buffer, rsi = length, writes to stderr
err_write:
    mov r8, rdi
    mov r9, rsi
.loop:
    test r9, r9
    jz .done
    mov edi, 2
    mov rsi, r8
    mov rdx, r9
    mov eax, SYS_WRITE
    syscall
    cmp rax, -4
    je .loop
    test rax, rax
    jle .done
    add r8, rax
    sub r9, rax
    jmp .loop
.done:
    ret

global err_cstr
err_cstr:
    push rdi
    call strlen
    mov rsi, rax
    pop rdi
    call err_write
    ret

global die
; rdi = message; prints "bx: <message>" to stderr and exits 1
die:
    push rdi
    call out_flush
    lea rdi, [rel err_prefix]
    call err_cstr
    pop rdi
    call err_cstr
    lea rdi, [rel newline]
    call err_cstr
    mov eax, SYS_EXIT
    mov edi, 1
    syscall
