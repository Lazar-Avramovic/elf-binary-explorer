BITS 64
default rel
%include "bx.inc"

extern open_and_map
extern streq
extern parse_u64
extern out_write
extern usage_error
extern die

global cmd_hex

section .bss
alignb 8
line_buf: resb 96

section .rodata
hex_digits: db "0123456789abcdef"

opt_offset: db "--offset", 0
opt_o: db "-o", 0
opt_length: db "--length", 0
opt_n: db "-n", 0
opt_end: db "--", 0
opt_offset_eq: db "--offset=", 0
opt_length_eq: db "--length=", 0

msg_unknown_opt: db "unknown hex option", 0
msg_missing_file: db "missing file", 0
msg_missing_value: db "missing option value", 0
msg_bad_number: db "invalid number", 0
msg_unexpected: db "unexpected argument", 0
msg_stdin: db "stdin is not supported; pass a regular file", 0

section .text

global cmd_hex
; rdi = arg count (without "bx hex"), rsi = argv for those args
cmd_hex:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi
    mov r13, rsi
    xor r14d, r14d
    mov r15, -1
    xor ebx, ebx
    xor ebp, ebp

.parse:
    cmp rbp, r12
    jae .parsed
    mov rdi, [r13 + rbp * 8]

    lea rsi, [rel opt_end]
    call streq
    test eax, eax
    jz .not_end

    inc rbp
    cmp rbp, r12
    jae .parsed
    test rbx, rbx
    jnz .unexpected
    mov rbx, [r13 + rbp * 8]
    inc rbp
    cmp rbp, r12
    jb .unexpected
    jmp .parsed

.not_end:
    cmp byte [rdi], '-'
    jne .set_file
    cmp byte [rdi + 1], 0
    je .stdin_unsupported

    lea rsi, [rel opt_offset_eq]
    call prefix_match
    test eax, eax
    jnz .offset_prefix
    lea rsi, [rel opt_length_eq]
    call prefix_match
    test eax, eax
    jnz .length_prefix

    lea rsi, [rel opt_offset]
    call streq
    test eax, eax
    jnz .do_offset
    lea rsi, [rel opt_o]
    call streq
    test eax, eax
    jnz .do_offset
    lea rsi, [rel opt_length]
    call streq
    test eax, eax
    jnz .do_length
    lea rsi, [rel opt_n]
    call streq
    test eax, eax
    jnz .do_length

    lea rsi, [rel opt_o]
    call prefix_match
    test eax, eax
    jnz .offset_prefix_short
    lea rsi, [rel opt_n]
    call prefix_match
    test eax, eax
    jnz .length_prefix_short

    lea rdi, [rel msg_unknown_opt]
    jmp usage_error

.offset_prefix:
    add rdi, 9
    cmp byte [rdi], 0
    je .missing_value
    jmp .set_offset_value
.length_prefix:
    add rdi, 9
    cmp byte [rdi], 0
    je .missing_value
    jmp .set_length_value
.offset_prefix_short:
    add rdi, 2
    cmp byte [rdi], 0
    je .missing_value
    jmp .set_offset_value
.length_prefix_short:
    add rdi, 2
    cmp byte [rdi], 0
    je .missing_value
    jmp .set_length_value

.do_offset:
    inc rbp
    cmp rbp, r12
    jae .missing_value
    mov rdi, [r13 + rbp * 8]
.set_offset_value:
    call parse_u64
    test edx, edx
    jz .bad_number
    mov r14, rax
    inc rbp
    jmp .parse

.do_length:
    inc rbp
    cmp rbp, r12
    jae .missing_value
    mov rdi, [r13 + rbp * 8]
.set_length_value:
    call parse_u64
    test edx, edx
    jz .bad_number
    mov r15, rax
    inc rbp
    jmp .parse

.set_file:
    test rbx, rbx
    jnz .unexpected
    mov rbx, rdi
    inc rbp
    jmp .parse

.stdin_unsupported:
    lea rdi, [rel msg_stdin]
    call die

.parsed:
    test rbx, rbx
    jz .missing_file

    mov rdi, rbx
    call open_and_map
    mov r12, rax
    mov r13, rdx

    cmp r14, r13
    jae .exit_ok
    mov rax, r13
    sub rax, r14
    cmp r15, rax
    jbe .length_ok
    mov r15, rax
.length_ok:
    test r15, r15
    jz .exit_ok

    add r12, r14
    mov r13, r15

.line_loop:
    mov r15, 16
    cmp r13, 16
    jae .line_len_ok
    mov r15, r13
.line_len_ok:
    lea rdi, [rel line_buf]
    mov rsi, r14
    mov edx, 16
    call hex_to_buf

    lea rdi, [rel line_buf]
    mov byte [rdi + 16], ' '
    mov byte [rdi + 17], ' '
    mov byte [rdi + 42], ' '
    lea r11, [rel hex_digits]
    xor r8d, r8d
.hex_loop:
    cmp r8, 16
    jae .hex_done
    mov r10, r8
    imul r10, r10, 3
    add r10, 18
    cmp r8, 8
    jb .no_extra
    inc r10
.no_extra:
    cmp r8, r15
    jae .hex_blank

    movzx eax, byte [r12 + r8]
    mov edx, eax
    shr edx, 4
    mov dl, [r11 + rdx]
    mov [rdi + r10], dl
    mov edx, eax
    and edx, 0xf
    mov dl, [r11 + rdx]
    mov [rdi + r10 + 1], dl
    mov byte [rdi + r10 + 2], ' '
    jmp .hex_next
.hex_blank:
    mov byte [rdi + r10], ' '
    mov byte [rdi + r10 + 1], ' '
    mov byte [rdi + r10 + 2], ' '
.hex_next:
    inc r8
    jmp .hex_loop
.hex_done:
    mov byte [rdi + 67], '|'
    xor r8d, r8d
.ascii_loop:
    cmp r8, r15
    jae .ascii_done
    movzx eax, byte [r12 + r8]
    cmp al, 0x20
    jb .dot
    cmp al, 0x7e
    ja .dot
    jmp .store_ascii
.dot:
    mov al, '.'
.store_ascii:
    mov [rdi + 68 + r8], al
    inc r8
    jmp .ascii_loop
.ascii_done:
    mov byte [rdi + 68 + r15], '|'
    mov byte [rdi + 69 + r15], 10
    mov rsi, 70
    add rsi, r15
    call out_write

    add r12, r15
    sub r13, r15
    add r14, r15
    test r13, r13
    jnz .line_loop

.exit_ok:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

.missing_file:
    lea rdi, [rel msg_missing_file]
    jmp usage_error
.missing_value:
    lea rdi, [rel msg_missing_value]
    jmp usage_error
.bad_number:
    lea rdi, [rel msg_bad_number]
    jmp usage_error
.unexpected:
    lea rdi, [rel msg_unexpected]
    jmp usage_error

hex_to_buf:
    ; rdi = buffer, rsi = value, edx = digits
    lea r8, [rel hex_digits]
    mov ecx, edx
    shl ecx, 2
    sub ecx, 4
    xor r9d, r9d
.loop:
    mov rax, rsi
    shr rax, cl
    and eax, 0xf
    mov al, [r8 + rax]
    mov [rdi + r9], al
    inc r9
    sub ecx, 4
    jns .loop
    ret

prefix_match:
    ; rdi = string, rsi = prefix; eax = 1 if the string starts with the prefix
    xor ecx, ecx
.loop:
    mov al, [rsi + rcx]
    test al, al
    jz .yes
    cmp byte [rdi + rcx], al
    jne .no
    inc rcx
    jmp .loop
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret
