%ifndef BX_INC
%define BX_INC

%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_OPEN        2
%define SYS_CLOSE       3
%define SYS_FSTAT       5
%define SYS_MMAP        9
%define SYS_MUNMAP      11
%define SYS_EXIT        60

%define O_RDONLY        0
%define O_NONBLOCK      0x800
%define PROT_READ       1
%define MAP_PRIVATE     2

%define OUT_BUF_SIZE    65536
%define STAT_BUF_SIZE   144

%define ELF64_EHDR_SIZE 64
%define ELF64_SHDR_SIZE 64
%define ELF64_PHDR_SIZE 56

%endif
