#!/usr/bin/env bash
# Build on-device UDP agent for OpenWrt mt76x8 (mipsle softfloat).
# Prefer tiny C + musl softfloat (Go static was ~3MB).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/cmd/leandns-discoverd/discoverd.c"
OUT="${ROOT}/package/leandns-manager/files/usr/sbin/leandns-discoverd"
TC_ROOT="${LEAN_DNS_MUSL_ROOT:-$ROOT/firmware/toolchain/mipsel-linux-muslsf-cross}"
TC_URL="${LEAN_DNS_MUSL_URL:-https://musl.cc/mipsel-linux-muslsf-cross.tgz}"
TC_ARCHIVE="$ROOT/firmware/toolchain/mipsel-linux-muslsf-cross.tgz"
CC_BIN="$TC_ROOT/bin/mipsel-linux-muslsf-gcc"

mkdir -p "$(dirname "$OUT")" "$ROOT/firmware/toolchain"

if [ ! -x "$CC_BIN" ]; then
  echo "→ downloading mipsel softfloat musl toolchain"
  if [ ! -f "$TC_ARCHIVE" ]; then
    if command -v curl >/dev/null; then
      curl -L --fail -o "$TC_ARCHIVE" "$TC_URL"
    else
      wget -O "$TC_ARCHIVE" "$TC_URL"
    fi
  fi
  tar -xzf "$TC_ARCHIVE" -C "$ROOT/firmware/toolchain"
fi

if [ ! -x "$CC_BIN" ]; then
  echo "softfloat gcc missing: $CC_BIN" >&2
  exit 1
fi

echo "→ C mipsel softfloat (static-pie)"
"$CC_BIN" -std=c99 -Os -pipe -static \
  -D_POSIX_C_SOURCE=200809L \
  -ffunction-sections -fdata-sections -Wl,--gc-sections -s \
  -o "$OUT" "$SRC"
file "$OUT"
ls -lh "$OUT"
strings "$OUT" | grep -E 'set_enabled|token_required|udp_set_enabled|LEANDNS1' | head -n 8 || true
echo "OK: $OUT"
echo "Tip: ./scripts/make-update-bundle.sh  # flat device update folder"
