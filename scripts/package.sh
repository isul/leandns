#!/usr/bin/env bash
# Assemble a portable package tree and sync web assets into the OpenWrt package.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/package/leandns-manager"
WEB_DST="$PKG/files/www/leandns"
OUT="$ROOT/firmware/leandns-manager-files"

echo "==> Sync web -> package"
rm -rf "$WEB_DST"
mkdir -p "$WEB_DST"
cp -a "$ROOT/web/." "$WEB_DST/"

echo "==> Stage installable file tree"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -a "$PKG/files/." "$OUT/"

# Ensure executables
find "$OUT" -type f \( -name '*.sh' -o -path '*/init.d/*' -o -path '*/uci-defaults/*' -o -path '*/rpcd/leandns' -o -name 'leandns-validate' \) -exec chmod +x {} \;

WEB_SIZE="$(du -sb "$WEB_DST" | awk '{print $1}')"
TREE_SIZE="$(du -sb "$OUT" | awk '{print $1}')"
echo "web_bytes=$WEB_SIZE"
echo "package_files_bytes=$TREE_SIZE"
echo "Staged at: $OUT"
