#!/usr/bin/env bash
# Assemble a flat on-device update folder from package + web sources.
# Output: firmware/update-bundle/ (gitignored). Does NOT flash hardware.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/package/leandns-manager/files"
WEB="$ROOT/web"
OUT="$ROOT/firmware/update-bundle"
DISC="$PKG/usr/sbin/leandns-discoverd"

"$ROOT/scripts/package.sh"

if [ ! -f "$DISC" ]; then
  echo "==> leandns-discoverd missing — building"
  "$ROOT/scripts/build-discoverd.sh"
fi

rm -rf "$OUT"
mkdir -p "$OUT"

cp -a "$PKG/usr/libexec/rpcd/leandns" "$OUT/leandns"
cp -a "$PKG/usr/share/rpcd/acl.d/leandns.json" "$OUT/leandns.json"
cp -a "$PKG/usr/libexec/leandns/apply-network.sh" "$OUT/apply-network.sh"
cp -a "$PKG/usr/sbin/leandns-discoverd" "$OUT/leandns-discoverd"
cp -a "$PKG/etc/init.d/leandns-discover" "$OUT/leandns-discover"
cp -a "$WEB/index.html" "$OUT/index.html"
cp -a "$WEB/js/app.js" "$OUT/app.js"
cp -a "$WEB/css/app.css" "$OUT/app.css"
# Flat /www root copy used by older devices that do not follow the leandns/ symlink yet
cp -a "$WEB/index.html" "$OUT/root-index.html"

cat > "$OUT/install-on-device.sh" <<'EOF'
#!/bin/sh
# Run ON device after scp files into /tmp/leandns-upd/
set -e
D="${1:-/tmp/leandns-upd}"
cp -a "$D/leandns" /usr/libexec/rpcd/leandns
cp -a "$D/leandns.json" /usr/share/rpcd/acl.d/leandns.json
cp -a "$D/apply-network.sh" /usr/libexec/leandns/apply-network.sh
cp -a "$D/leandns-discoverd" /usr/sbin/leandns-discoverd
cp -a "$D/leandns-discover" /etc/init.d/leandns-discover
cp -a "$D/index.html" /www/leandns/index.html
cp -a "$D/app.js" /www/leandns/js/app.js
cp -a "$D/app.css" /www/leandns/css/app.css
[ -f "$D/root-index.html" ] && cp -a "$D/root-index.html" /www/index.html

chmod +x /usr/libexec/rpcd/leandns /usr/libexec/leandns/apply-network.sh /usr/sbin/leandns-discoverd /etc/init.d/leandns-discover
mkdir -p /etc/leandns
[ -s /etc/leandns/udp.token ] || tr -dc A-Za-z0-9 </dev/urandom | head -c 24 > /etc/leandns/udp.token
chmod 600 /etc/leandns/udp.token
/etc/init.d/leandns-discover enable
/etc/init.d/leandns-discover restart
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
echo OK
EOF
chmod +x "$OUT/install-on-device.sh" "$OUT/apply-network.sh" "$OUT/leandns" "$OUT/leandns-discoverd" "$OUT/leandns-discover"

echo "Staged at: $OUT"
ls -lh "$OUT"
