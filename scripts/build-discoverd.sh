#!/usr/bin/env bash
# Build on-device UDP agent for OpenWrt mt76x8 (mipsle softfloat).
# Prefer Go softfloat: musl.cc C toolchains are often hard-float and won't answer on device.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/package/leandns-manager/files/usr/sbin/leandns-discoverd"

mkdir -p "$(dirname "$OUT")"
echo "→ go mipsle softfloat"
CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat \
  go build -trimpath -ldflags='-s -w' \
  -o "$OUT" "${ROOT}/cmd/leandns-discoverd"
file "$OUT"
ls -lh "$OUT"
strings "$OUT" | grep -E 'set_enabled|token_required|udp_set_enabled' | head -n 5 || true
echo "OK: $OUT"
echo "Tip: ./scripts/make-update-bundle.sh  # flat device update folder"
