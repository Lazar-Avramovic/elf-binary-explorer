#!/usr/bin/env bash
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PREFIX=${PREFIX:-/usr/local}
DESTDIR=${DESTDIR:-}
STRIP=${STRIP:-1}
BIN="$ROOT/build/bx"

if [ ! -x "$BIN" ]; then
    echo "install.sh: build/bx is missing; run 'bash build.sh' first" >&2
    exit 1
fi

install -d "$DESTDIR$PREFIX/bin" \
    "$DESTDIR$PREFIX/share/man/man1" \
    "$DESTDIR$PREFIX/share/bash-completion/completions" \
    "$DESTDIR$PREFIX/share/zsh/site-functions" \
    "$DESTDIR$PREFIX/share/fish/vendor_completions.d"

install -m 0755 "$BIN" "$DESTDIR$PREFIX/bin/bx"
if [ "$STRIP" != "0" ]; then
    if ! command -v strip >/dev/null 2>&1; then
        echo "install.sh: strip not found; use STRIP=0 to install unstripped" >&2
        exit 1
    fi
    if ! strip "$DESTDIR$PREFIX/bin/bx"; then
        echo "install.sh: strip failed; use STRIP=0 to install unstripped" >&2
        exit 1
    fi
fi
install -m 0644 "$ROOT/bx.1" "$DESTDIR$PREFIX/share/man/man1/bx.1"
install -m 0644 "$ROOT/completions/bx.bash" "$DESTDIR$PREFIX/share/bash-completion/completions/bx"
install -m 0644 "$ROOT/completions/_bx" "$DESTDIR$PREFIX/share/zsh/site-functions/_bx"
install -m 0644 "$ROOT/completions/bx.fish" "$DESTDIR$PREFIX/share/fish/vendor_completions.d/bx.fish"

printf 'installed bx to %s\n' "$DESTDIR$PREFIX"
