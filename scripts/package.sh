#!/usr/bin/env bash
# Assemble a portable package tree and sync web assets into the OpenWrt package.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/package/leandns-manager"
WWW="$PKG/files/www"
WEB_DST="$WWW/leandns"
OUT="$ROOT/firmware/leandns-manager-files"

echo "==> Sync web -> package"
rm -rf "$WEB_DST"
mkdir -p "$WEB_DST"
cp -a "$ROOT/web/." "$WEB_DST/"

# Same layout as on-device www-root.sh: /www mirrors /www/leandns
mkdir -p "$WWW/cgi-bin"
ln -sfn leandns/index.html "$WWW/index.html"
ln -sfn leandns/css "$WWW/css"
ln -sfn leandns/js "$WWW/js"
ln -sfn leandns/img "$WWW/img"

echo "==> Stage installable file tree"
rm -rf "$OUT"
mkdir -p "$OUT"
cp -a "$PKG/files/." "$OUT/"

# Silence Image Builder "process substitution" Error on host dash; device ash is fine.
if [ -f "$PKG/files/etc/init.d/adblock-lean" ]; then
  "$ROOT/scripts/patch-adblock-lean-ib.sh" "$PKG/files/etc/init.d/adblock-lean"
  "$ROOT/scripts/patch-adblock-lean-ib.sh" "$OUT/etc/init.d/adblock-lean"
fi

# adblock-lean refuses to start without an md5 registry of its scripts.
if [ -f "$OUT/etc/init.d/adblock-lean" ] && [ -f "$OUT/usr/lib/adblock-lean/abl-lib.sh" ]; then
  mkdir -p "$OUT/etc/adblock-lean"
  (
    cd "$OUT"
    md5sum       etc/init.d/adblock-lean       usr/lib/adblock-lean/abl-lib.sh       usr/lib/adblock-lean/abl-process.sh |
      sed 's#^\([0-9a-f]*\)  #\1  /#' > etc/adblock-lean/abl-reg.md5
  )
  # Also keep a copy in the package source tree for future builds/syncs.
  cp -a "$OUT/etc/adblock-lean/abl-reg.md5" "$PKG/files/etc/adblock-lean/abl-reg.md5"
fi

# Enable adblock-lean at boot without running its full enable() on the build host
# (DISABLED_SERVICES=adblock-lean in build.sh; rc.d links keep it enabled on device).
mkdir -p "$OUT/etc/rc.d" "$PKG/files/etc/rc.d"
ln -sfn ../init.d/adblock-lean "$OUT/etc/rc.d/S99adblock-lean"
ln -sfn ../init.d/adblock-lean "$OUT/etc/rc.d/K04adblock-lean"
ln -sfn ../init.d/adblock-lean "$PKG/files/etc/rc.d/S99adblock-lean"
ln -sfn ../init.d/adblock-lean "$PKG/files/etc/rc.d/K04adblock-lean"

# Ensure executables
find "$OUT" -type f \( -name '*.sh' -o -path '*/init.d/*' -o -path '*/uci-defaults/*' -o -path '*/rpcd/leandns' -o -path '*/cgi-bin/*' -o -name 'leandns-validate' -o -name 'leandns-discoverd' \) -exec chmod +x {} \;

WEB_SIZE="$(du -sb "$WEB_DST" | awk '{print $1}')"
TREE_SIZE="$(du -sb "$OUT" | awk '{print $1}')"
echo "web_bytes=$WEB_SIZE"
echo "package_files_bytes=$TREE_SIZE"
echo "Staged at: $OUT"
