BITS 64
global _start

section .text
_start:
    mov eax, 60
    xor edi, edi
    syscall

section .rodata
rodata_msg: db "rodata", 0

section .data
data_msg: db "data", 0

section .bss
bss_buf: resb 16
