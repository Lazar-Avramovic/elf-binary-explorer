BITS 64
default rel

section .text

global strlen
strlen:
    xor eax, eax
.loop:
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

global streq
streq:
    xor ecx, ecx
.loop:
    mov al, [rdi + rcx]
    mov dl, [rsi + rcx]
    cmp al, dl
    jne .no
    test al, al
    jz .yes
    inc rcx
    jmp .loop
.no:
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

global safe_strlen
; rdi = pointer, rsi = maximum bytes; stops at NUL or the cap
safe_strlen:
    xor eax, eax
.loop:
    cmp rax, rsi
    jae .done
    cmp byte [rdi + rax], 0
    je .done
    inc rax
    jmp .loop
.done:
    ret

global parse_u64
; rdi = decimal or 0x-prefixed string; rax = value, edx = 1 on success
parse_u64:
    xor eax, eax
    xor edx, edx
    mov r8, rdi
    movzx ecx, byte [r8]
    test cl, cl
    jz .fail
    cmp cl, '0'
    jne .dec
    movzx ecx, byte [r8 + 1]
    or cl, 0x20
    cmp cl, 'x'
    jne .dec
    add r8, 2
    movzx ecx, byte [r8]
    test cl, cl
    jz .fail
.hex_loop:
    movzx ecx, byte [r8]
    test cl, cl
    jz .ok
    cmp cl, '0'
    jb .fail
    cmp cl, '9'
    jbe .hex_digit
    or cl, 0x20
    cmp cl, 'a'
    jb .fail
    cmp cl, 'f'
    ja .fail
    sub cl, ('a' - 10)
    jmp .hex_add
.hex_digit:
    sub cl, '0'
.hex_add:
    shl rax, 4
    jc .fail
    add rax, rcx
    jc .fail
    inc r8
    jmp .hex_loop
.dec:
    mov r8, rdi
    mov r9, 10
.dec_loop:
    movzx ecx, byte [r8]
    test cl, cl
    jz .ok
    cmp cl, '0'
    jb .fail
    cmp cl, '9'
    ja .fail
    sub cl, '0'
    mul r9
    test rdx, rdx
    jnz .fail
    add rax, rcx
    jc .fail
    inc r8
    jmp .dec_loop
.ok:
    mov edx, 1
    ret
.fail:
    xor edx, edx
    ret
