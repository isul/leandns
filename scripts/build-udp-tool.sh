#!/usr/bin/env bash
# Cross-build PC UDP tool (not the on-device discoverd).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/dist/leandns-tool"
mkdir -p "$OUT"
cd "$ROOT"

build() {
  local goos="$1" goarch="$2" name="$3"
  echo "→ $name ($goos/$goarch)"
  CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
    go build -trimpath -ldflags="-s -w" \
    -o "${OUT}/${name}" ./cmd/leandns-tool
}

build windows amd64 leandns-tool-windows-amd64.exe
build linux   amd64 leandns-tool-linux-amd64
build linux   arm64 leandns-tool-linux-arm64
build darwin  amd64 leandns-tool-darwin-amd64
build darwin  arm64 leandns-tool-darwin-arm64

ls -lh "$OUT"
echo "OK: binaries in $OUT"
