#!/usr/bin/env bash
#  Build liminade: Ada sources -> freestanding ELF64 -> PE32+ UEFI image.
#
#  nixpkgs has no Ada compiler that targets PE/COFF, so the image is produced
#  in two stages: native GNAT emits a freestanding ELF executable (no libc, no
#  crt, entry point at the efi64_entry ABI shim), and tools/elf2pe.py maps the
#  ELF load segments onto a PE32+ image.
set -euo pipefail

cd "$(dirname "$0")"

SRC=src
BUILD=build
OUT="$BUILD/liminade.efi"
ELF="$BUILD/liminade.elf"
IMAGE_BASE=${IMAGE_BASE:-0x10000000}

#  Locate the GNAT runtime library (adalib).  gnatls reports the search path
#  even when gcc is the generic C driver wrapper, which knows nothing about
#  libgnat.  (The full output is captured first: pipefail would otherwise
#  turn the reader's early exit into SIGPIPE.)
GNATLS_OUT=$(gnatls -v 2>/dev/null || true)
ADALIB=$(printf '%s\n' "$GNATLS_OUT" |
         grep -m1 '/adalib[[:space:]]*$' |
         sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)
if [ -z "${ADALIB:-}" ] || [ ! -f "$ADALIB/libgnat.a" ]; then
    ADALIB=$(dirname "$(gcc -print-file-name=libgnat.a)")
fi
if [ ! -f "$ADALIB/libgnat.a" ]; then
    echo "build: cannot locate libgnat.a (looked in ${ADALIB:-<nothing>})" >&2
    echo "build: run inside 'nix develop'" >&2
    exit 1
fi

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> compiling Ada sources"
#  gnatmake's -cargs parsing rejects multiple GCC switches, so the freestanding
#  flags are supplied through ADAFLAGS (and verified by the nm check below).
export ADAFLAGS="-fno-pie -fno-stack-protector -mno-red-zone -fno-omit-frame-pointer"
gnatmake -c \
    -O2 -gnat2012 -gnatp \
    -I"$SRC" -I"$SRC/efi" \
    -D "$BUILD" \
    "$SRC/liminade.adb"

echo "==> assembling shims"
as -o "$BUILD/efi64_entry.o" "$SRC/efi64_entry.s"
as -o "$BUILD/com1_io.o" "$SRC/com1_io.s"
as -o "$BUILD/ms_abi.o" "$SRC/ms_abi.s"
as -o "$BUILD/jump.o" "$SRC/jump.s"

echo "==> linking freestanding ELF"
gcc -nostdlib -static -no-pie \
    -Wl,--entry=efi64_entry \
    -Wl,-Ttext-segment="$IMAGE_BASE" \
    -o "$ELF" \
    "$BUILD"/*.o \
    -L"$ADALIB" -lgnat -lgcc

echo "==> checking for external (libc/loader) dependencies"
UNDEF=$(nm -u "$ELF" | awk '{print $2}' | grep -v '^$' || true)
if [ -n "$UNDEF" ]; then
    echo "build: warning, undefined symbols:" >&2
    echo "$UNDEF" >&2
fi

echo "==> repackaging as PE32+"
python3 tools/elf2pe.py --verbose "$ELF" "$OUT"

echo "==> PE summary"
objdump -f "$OUT" | sed -n '1,3p'
objdump -p "$OUT" | grep -E 'ImageBase|AddressOfEntryPoint|Subsystem|SizeOfImage|DllCharacteristics'

echo "built: $OUT"
