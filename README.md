# bx

[![CI](https://github.com/Lazar-Avramovic/elf-binary-explorer/actions/workflows/ci.yml/badge.svg)](https://github.com/Lazar-Avramovic/elf-binary-explorer/actions/workflows/ci.yml)

A tiny, static ELF64 binary explorer written in x86-64 assembly. No libc, no
dynamic loader, no runtime dependencies. One file you can drop into a scratch
container or a rescue shell and run immediately.

By [Lazar Avramovic](https://github.com/Lazar-Avramovic).

`bx` answers the first questions you ask about an unfamiliar executable: what
is it, what sections does it have, and what do the bytes look like?

```text
$ bx info /bin/ls
File:      /bin/ls
Size:      151344 bytes
Format:    ELF64 little-endian
Type:      DYN (3)
Machine:   x86-64 (62)
Entry:     0x00000000000061d0
Sections:  31
Segments:  13
```

Current build: **27,968 bytes unstripped, 14,280 bytes stripped**.

## Measured

WSL2 Ubuntu x86-64 on ext4, 60 runs after 5 warmups, full process startup
timed with Python's `perf_counter`. Single-machine medians; min–max in
parentheses. Your hardware will differ.

| Workload | `bx` | Reference | Speedup |
|---|---:|---:|---:|
| `info /bin/ls` | 0.41 ms (0.32–0.86) | `readelf -h`: 1.46 ms (1.06–2.09) | 3.6x |
| `sections /bin/bash` | 0.41 ms (0.32–0.70) | `readelf -SW`: 1.61 ms (1.16–2.79) | 3.9x |
| `hex -n 64 /bin/bash` | 0.40 ms (0.31–0.80) | `xxd -l 64`: 0.73 ms (0.61–1.41) | 1.8x |

The point is not a benchmark record. It is the startup profile of a small
static binary that does not wait for a dynamic loader or a large toolchain.

## Build

Requirements: Linux x86-64, NASM 2.16 or newer, and GNU `ld` from binutils.
On Windows, build in WSL. If NASM is only on the Windows side, point `NASM`
at it (the path below is an example); `ld` must be WSL's native linker.

```sh
bash build.sh
./build/bx --version

# WSL, with NASM only on Windows:
NASM=/mnt/c/path/to/nasm.exe bash build.sh
```

`make` is optional: `make`, `make test`, `make install`.

## Install

```sh
sudo bash install.sh
# or, without root:
PREFIX="$HOME/.local" bash install.sh
```

This installs the binary, `bx.1`, and bash/zsh/fish completions. The installed
binary is stripped by default; set `STRIP=0` to keep symbols. If `strip` is
missing or fails, installation fails unless `STRIP=0` is set.

## Use

```sh
bx info ./program
bx sections ./program
bx hex ./program
bx hex -o 0x100 -n 64 ./program
bx hex --offset=0x100 --length=64 ./program
```

`info` prints the ELF header summary. `sections` prints an aligned table with
names, types, flags, addresses, offsets, and sizes. `hex` prints a classic
hex + ASCII dump.

`info` and `sections` accept an optional `--` before or after the file. `hex`
accepts `-o/--offset`, `-n/--length`, combined short values such as `-n64`,
and `--` to end option parsing.

## Safety

`bx` treats its input as untrusted:

- Section names are sanitized. Non-printable bytes are replaced with `.`, so a
  malicious ELF cannot inject terminal escapes or newlines into the table.
- Section, segment and name tables are bounds-checked before access.
- Non-regular files (devices, FIFOs, sockets) are rejected. Zero-size
  pseudo-files that do not report a size are rejected instead of silently
  producing empty output.
- Only ELF64 little-endian files are accepted. 32-bit and big-endian ELF are
  rejected with a clear error.
- stdin is not supported in this version; pass a regular file.

The test suite includes malformed headers, truncated tables, out-of-bounds name
indices, extended numbering, and fuzzed ELF headers.

## Test

```sh
bash build.sh
bash tests/run_tests.sh
```

On WSL with NASM only on the Windows side, prefix the test command with the
same `NASM=...` assignment.

The shell suite uses `readelf` and the raw file bytes as oracles. It fails red
on zero tests or zero positive controls. A Python regression suite covers table
layout, five-flag rows, GNU section types, `SHF_EXCLUDE`/`SHF_GNU_RETAIN`,
ANSI-safe names, CLI forms, full-u64 offsets, extended tables, full-file hex
accuracy, and a deterministic fuzz pass. `tests/regressions.py` can be run
directly.

## Limits

- ELF64 little-endian only; x86-64 host.
- No `segments` listing yet; `info` reports the count only.
- No JSON, color, stdin, PE/COFF, or disassembly.
- Section names are shown up to 40 characters; longer names end in `..`.
- No distro packages yet; build from source.

## Roadmap

- `segments` with type, flags, vaddr, filesz/memsz, align, and `PT_INTERP`.
- A `check` mode for hardening issues: W^X/RWX segments, missing NX stack,
  missing build-id, overlapping tables.
- Richer `info`: OSABI, PT_INTERP, build-id, PIE/static classification, RELRO.
- JSON output and optional color.

## License

MIT. See [LICENSE](LICENSE). © 2026 Lazar Avramovic.
