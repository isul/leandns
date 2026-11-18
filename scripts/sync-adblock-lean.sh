#!/usr/bin/env bash
# Refresh vendored adblock-lean from upstream and copy into package/firmware trees.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/third_party/adblock-lean"
BASE="https://raw.githubusercontent.com/lynxthecat/adblock-lean/master"

mkdir -p "$VENDOR/etc/init.d" "$VENDOR/usr/lib/adblock-lean"
curl -fsSL "$BASE/adblock-lean" -o "$VENDOR/etc/init.d/adblock-lean"
curl -fsSL "$BASE/usr/lib/adblock-lean/abl-lib.sh" -o "$VENDOR/usr/lib/adblock-lean/abl-lib.sh"
curl -fsSL "$BASE/usr/lib/adblock-lean/abl-process.sh" -o "$VENDOR/usr/lib/adblock-lean/abl-process.sh"
chmod +x "$VENDOR/etc/init.d/adblock-lean"
curl -fsSL "https://api.github.com/repos/lynxthecat/adblock-lean/commits/master" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])' \
  > "$VENDOR/COMMIT" || date -u +%Y%m%d > "$VENDOR/COMMIT"

for DEST in \
  "$ROOT/package/leandns-manager/files" \
  "$ROOT/firmware/files" \
  "$ROOT/firmware/leandns-manager-files"
do
  [ -d "$(dirname "$DEST")" ] || continue
  mkdir -p "$DEST/etc/init.d" "$DEST/usr/lib/adblock-lean" "$DEST/etc/adblock-lean"
  cp -a "$VENDOR/etc/init.d/adblock-lean" "$DEST/etc/init.d/adblock-lean"
  cp -a "$VENDOR/usr/lib/adblock-lean/"*.sh "$DEST/usr/lib/adblock-lean/"
  cp -a "$ROOT/configs/adblock-lean.mini.conf" "$DEST/etc/adblock-lean/config"
  cp -a "$ROOT/configs/adblock-lean.mini.conf" "$DEST/etc/adblock-lean/config.mini"
done

echo "OK: adblock-lean synced ($(cat "$VENDOR/COMMIT" | cut -c1-12))"
