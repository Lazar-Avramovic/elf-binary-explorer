#!/usr/bin/env bash
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

BX="$ROOT/build/bx"
TMP="$ROOT/build/test-tmp.$$"
rm -rf "$TMP"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

TESTS=0
PASS=0
FAIL=0
POS=0
OUT="$TMP/out"
ERR="$TMP/err"
RC=0

ok() {
    TESTS=$((TESTS + 1))
    PASS=$((PASS + 1))
    printf 'ok %d - %s\n' "$TESTS" "$1"
}

bad() {
    TESTS=$((TESTS + 1))
    FAIL=$((FAIL + 1))
    printf 'not ok %d - %s\n' "$TESTS" "$1"
}

run() {
    "$@" >"$OUT" 2>"$ERR"
    RC=$?
}

check_rc() {
    if [ "$RC" -eq "$1" ]; then
        ok "$2"
    else
        bad "$2 (rc=$RC, wanted $1)"
        sed -n '1,4p' "$ERR" | sed 's/^/  /'
    fi
}

check_out() {
    if grep -qF -- "$2" "$OUT"; then
        ok "$1"
    else
        bad "$1 (missing: $2)"
        sed -n '1,4p' "$OUT" | sed 's/^/  /'
    fi
}

check_err() {
    if grep -qF -- "$2" "$ERR"; then
        ok "$1"
    else
        bad "$1 (missing: $2)"
        sed -n '1,4p' "$ERR" | sed 's/^/  /'
    fi
}

check_empty_out() {
    if [ ! -s "$OUT" ]; then
        ok "$1"
    else
        bad "$1 (output not empty)"
        sed -n '1,3p' "$OUT" | sed 's/^/  /'
    fi
}

if ! command -v readelf >/dev/null 2>&1; then
    echo "readelf is required" >&2
    exit 1
fi

NASM_BIN=${NASM:-}
if [ -z "$NASM_BIN" ]; then
    if command -v nasm >/dev/null 2>&1; then
        NASM_BIN=nasm
    elif command -v nasm.exe >/dev/null 2>&1; then
        NASM_BIN=nasm.exe
    else
        echo "nasm is required (set NASM=/path/to/nasm)" >&2
        exit 1
    fi
fi
LD_BIN=${LD:-ld}

if ! bash "$ROOT/build.sh" >/dev/null; then
    echo "build failed" >&2
    exit 1
fi

cp "$ROOT/tests/fixtures/tiny.asm" "$TMP/tiny.asm"
if ! (cd "$TMP" && "$NASM_BIN" -f elf64 -o tiny.o tiny.asm && "$LD_BIN" -o tiny tiny.o); then
    echo "fixture build failed" >&2
    exit 1
fi
FIXTURE="$TMP/tiny"
TINY_OBJ="$TMP/tiny.o"

printf 'hello\n' > "$TMP/text"
: > "$TMP/empty"
printf 'abc' > "$TMP/tiny4"
dd if=/dev/zero of="$TMP/zero64" bs=64 count=1 status=none
head -c 64 "$FIXTURE" > "$TMP/trunc"
cp "$FIXTURE" "$TMP/class32"
printf '\x01' | dd of="$TMP/class32" bs=1 seek=4 conv=notrunc status=none
cp "$FIXTURE" "$TMP/bigend"
printf '\x02' | dd of="$TMP/bigend" bs=1 seek=5 conv=notrunc status=none
cp "$FIXTURE" "$TMP/-dash"

run "$BX" --version
check_rc 0 "version exits 0"
if [ "$(cat "$OUT")" = "bx 0.1.0" ]; then
    ok "version string"
else
    bad "version string"
fi

run "$BX" --help
check_rc 0 "help exits 0"
check_out "help shows Usage" "Usage:"
check_out "help lists info" "bx info"

run "$BX"
check_rc 2 "no command exits 2"
check_err "no command explains itself" "no command given"

run "$BX" bogus
check_rc 2 "unknown command exits 2"
check_err "unknown command is named" "unknown command"

run "$BX" info "$FIXTURE"
check_rc 0 "info fixture exits 0"
check_out "fixture is ELF64" "ELF64"
check_out "fixture machine" "x86-64"
if [ "$RC" -eq 0 ]; then
    POS=$((POS + 1))
fi
re_entry=$(readelf -h "$FIXTURE" | awk -F: '/Entry point address/ {gsub(/[ \t]/, "", $2); print $2}')
bx_entry=$(awk '/^Entry:/ {print $2}' "$OUT")
if [ -n "$re_entry" ] && [ -n "$bx_entry" ] && [ $((bx_entry)) -eq $((re_entry)) ]; then
    ok "fixture entry matches readelf"
else
    bad "fixture entry matches readelf (bx=$bx_entry readelf=$re_entry)"
fi
re_secs=$(readelf -h "$FIXTURE" | awk -F: '/Number of section headers/ {gsub(/[ \t]/, "", $2); print $2}')
bx_secs=$(awk '/^Sections:/ {print $2}' "$OUT")
if [ -n "$re_secs" ] && [ "$bx_secs" = "$re_secs" ]; then
    ok "fixture section count matches readelf"
else
    bad "fixture section count matches readelf (bx=$bx_secs readelf=$re_secs)"
fi

run "$BX" info "$TINY_OBJ"
check_rc 0 "info relocatable exits 0"
check_out "relocatable type" "REL"
check_out "relocatable has no segments" "Segments:  0"
if [ "$RC" -eq 0 ]; then
    POS=$((POS + 1))
fi

run "$BX" info /bin/ls
check_rc 0 "info /bin/ls exits 0"
check_out "/bin/ls is DYN" "DYN"
if [ "$RC" -eq 0 ]; then
    POS=$((POS + 1))
fi

run "$BX" sections "$FIXTURE"
check_rc 0 "sections fixture exits 0"
for name in .text .rodata .data .bss .shstrtab; do
    check_out "section $name present" "$name"
done

run "$BX" hex -n 4 "$FIXTURE"
check_rc 0 "hex first four exits 0"
check_out "hex magic" "7f 45 4c 46"
if [ "$RC" -eq 0 ]; then
    POS=$((POS + 1))
fi

run "$BX" hex -o 0x10 -n 16 "$FIXTURE"
check_rc 0 "hex offset exits 0"
if [ "$(wc -l < "$OUT")" -eq 1 ] && head -1 "$OUT" | grep -q '^0000000000000010 '; then
    ok "hex offset line"
else
    bad "hex offset line"
    sed -n '1,3p' "$OUT" | sed 's/^/  /'
fi

run "$BX" hex -n 17 "$FIXTURE"
check_rc 0 "hex 17 bytes exits 0"
if [ "$(wc -l < "$OUT")" -eq 2 ]; then
    ok "hex 17 bytes uses two lines"
else
    bad "hex 17 bytes uses two lines"
fi

run "$BX" hex "$TMP/text"
check_rc 0 "hex non-ELF exits 0"
check_out "hex text bytes" "68 65 6c 6c 6f"
if [ "$RC" -eq 0 ]; then
    POS=$((POS + 1))
fi

(cd "$TMP" && "$BX" hex -n 4 -- -dash) >"$OUT" 2>"$ERR"
RC=$?
check_rc 0 "hex -- accepts dash filename"
check_out "hex -- dumps dash file" "7f 45 4c 46"

run "$BX" info "$TMP/empty"
check_rc 1 "empty is rejected"
check_err "empty is not ELF" "not an ELF file"

run "$BX" hex "$TMP/empty"
check_rc 0 "hex empty exits 0"
check_empty_out "hex empty writes nothing"

run "$BX" info "$TMP/tiny4"
check_rc 1 "four bytes rejected"
check_err "four bytes not ELF" "not an ELF file"

run "$BX" info "$TMP/zero64"
check_rc 1 "zero header rejected"

run "$BX" info "$TMP/trunc"
check_rc 1 "truncated ELF rejected"
check_err "truncated section table" "malformed section table"

run "$BX" info "$TMP/class32"
check_rc 1 "32-bit rejected"
check_err "32-bit message" "only 64-bit ELF"

run "$BX" info "$TMP/bigend"
check_rc 1 "big-endian rejected"
check_err "big-endian message" "only little-endian ELF"

run "$BX" info "$TMP"
check_rc 1 "directory rejected"
check_err "directory message" "is a directory"

run "$BX" info "$TMP/nope"
check_rc 1 "missing file rejected"
check_err "missing file message" "cannot open file"

run "$BX" hex
check_rc 2 "hex without file exits 2"
check_err "hex without file message" "missing file"

run "$BX" hex -o
check_rc 2 "hex missing option value"
check_err "missing option value message" "missing option value"

run "$BX" hex -n nope "$FIXTURE"
check_rc 2 "hex invalid number"
check_err "invalid number message" "invalid number"

run "$BX" hex "$FIXTURE" extra
check_rc 2 "hex extra argument"
check_err "extra argument message" "unexpected argument"

run "$BX" hex -z "$FIXTURE"
check_rc 2 "hex unknown option"
check_err "unknown option message" "unknown hex option"

run "$BX" info
check_rc 2 "info without file"
run "$BX" sections
check_rc 2 "sections without file"

if command -v python3 >/dev/null 2>&1; then
    if python3 "$ROOT/tests/regressions.py" "$BX"; then
        ok "field-level regression suite"
    else
        bad "field-level regression suite"
    fi
else
    bad "python3 available for the field-level regression suite"
fi

if [ "$TESTS" -eq 0 ]; then
    echo "no tests ran" >&2
    exit 1
fi
if [ "$POS" -eq 0 ]; then
    echo "no positive control ran" >&2
    exit 1
fi
printf 'tests=%d pass=%d fail=%d positive=%d\n' "$TESTS" "$PASS" "$FAIL" "$POS"
[ "$FAIL" -eq 0 ]
