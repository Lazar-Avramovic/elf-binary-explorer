#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

case "$(uname -s)" in
  Linux) ;;
  *) echo "bx: build requires Linux (use WSL on Windows)" >&2; exit 1 ;;
esac

if [ -z "${NASM:-}" ]; then
  if command -v nasm >/dev/null 2>&1; then
    NASM=nasm
  elif command -v nasm.exe >/dev/null 2>&1; then
    NASM=nasm.exe
  else
    echo "bx: nasm not found (set NASM=/path/to/nasm)" >&2
    exit 1
  fi
fi

LD=${LD:-ld}
BUILD=build
mkdir -p "$BUILD"

NASMFLAGS="-f elf64 -I src/"
if [ "${DEBUG:-0}" = "1" ]; then
  NASMFLAGS="$NASMFLAGS -g -F dwarf"
fi

OBJ=()
for src in src/*.asm; do
  obj="$BUILD/$(basename "${src%.asm}").o"
  "$NASM" $NASMFLAGS -o "$obj" "$src"
  OBJ+=("$obj")
done

"$LD" -z noexecstack -o "$BUILD/bx" "${OBJ[@]}"
echo "built $BUILD/bx"
