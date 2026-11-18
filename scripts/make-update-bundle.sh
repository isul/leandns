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
cp -a "$PKG/usr/libexec/leandns/apply-dns.sh" "$OUT/apply-dns.sh"
cp -a "$PKG/usr/libexec/leandns/adblock-ctl.sh" "$OUT/adblock-ctl.sh"
cp -a "$PKG/usr/libexec/leandns/status.sh" "$OUT/status.sh"
cp -a "$PKG/usr/libexec/leandns/stats-ctl.sh" "$OUT/stats-ctl.sh"
cp -a "$PKG/usr/libexec/leandns/firmware-ctl.sh" "$OUT/firmware-ctl.sh"
cp -a "$PKG/www/cgi-bin/leandns-fw-upload" "$OUT/leandns-fw-upload"
cp -a "$PKG/usr/sbin/leandns-discoverd" "$OUT/leandns-discoverd"
cp -a "$PKG/etc/init.d/leandns-discover" "$OUT/leandns-discover"
cp -a "$PKG/etc/init.d/leandns-stats" "$OUT/leandns-stats"
cp -a "$WEB/index.html" "$OUT/index.html"
cp -a "$WEB/js/app.js" "$OUT/app.js"
cp -a "$WEB/js/api.js" "$OUT/api.js"
cp -a "$WEB/css/app.css" "$OUT/app.css"
# Flat /www root copy used by older devices that do not follow the leandns/ symlink yet
cp -a "$WEB/index.html" "$OUT/root-index.html"

cat > "$OUT/install-on-device.sh" <<'EOF'
#!/bin/sh
# Run ON device after scp files into /tmp/leandns-upd/
set -e
D="${1:-/tmp/leandns-upd}"
[ -x /usr/libexec/leandns/stats-ctl.sh ] && /usr/libexec/leandns/stats-ctl.sh pause || true
[ -x "$D/stats-ctl.sh" ] && /bin/sh "$D/stats-ctl.sh" pause || true
cp -a "$D/leandns" /usr/libexec/rpcd/leandns
cp -a "$D/leandns.json" /usr/share/rpcd/acl.d/leandns.json
cp -a "$D/apply-network.sh" /usr/libexec/leandns/apply-network.sh
cp -a "$D/apply-dns.sh" /usr/libexec/leandns/apply-dns.sh
cp -a "$D/adblock-ctl.sh" /usr/libexec/leandns/adblock-ctl.sh
cp -a "$D/status.sh" /usr/libexec/leandns/status.sh
cp -a "$D/stats-ctl.sh" /usr/libexec/leandns/stats-ctl.sh
cp -a "$D/firmware-ctl.sh" /usr/libexec/leandns/firmware-ctl.sh
mkdir -p /www/cgi-bin
cp -a "$D/leandns-fw-upload" /www/cgi-bin/leandns-fw-upload
cp -a "$D/leandns-discoverd" /usr/sbin/leandns-discoverd
cp -a "$D/leandns-discover" /etc/init.d/leandns-discover
cp -a "$D/leandns-stats" /etc/init.d/leandns-stats
cp -a "$D/index.html" /www/leandns/index.html
cp -a "$D/app.js" /www/leandns/js/app.js
[ -f "$D/api.js" ] && cp -a "$D/api.js" /www/leandns/js/api.js
cp -a "$D/app.css" /www/leandns/css/app.css
[ -f "$D/root-index.html" ] && cp -a "$D/root-index.html" /www/index.html

chmod +x /usr/libexec/rpcd/leandns /usr/libexec/leandns/*.sh /usr/sbin/leandns-discoverd /etc/init.d/leandns-discover /etc/init.d/leandns-stats /www/cgi-bin/leandns-fw-upload
# Enable RAM-only block stats for the dashboard (cleared on reboot).
uci -q set leandns.main.query_log=1
uci -q set leandns.main.query_log_max=20
uci -q set leandns.main.upgrade_headroom_kb=6144
uci -q commit leandns >/dev/null 2>&1 || true
mkdir -p /etc/leandns
[ -s /etc/leandns/udp.token ] || tr -dc A-Za-z0-9 </dev/urandom | head -c 24 > /etc/leandns/udp.token
chmod 600 /etc/leandns/udp.token
/usr/libexec/leandns/apply-dns.sh --apply >/dev/null 2>&1 || true
/etc/init.d/leandns-discover enable
/etc/init.d/leandns-discover restart
/etc/init.d/leandns-stats enable
/etc/init.d/leandns-stats restart
/usr/libexec/leandns/stats-ctl.sh resume >/dev/null 2>&1 || true
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
echo OK
EOF
chmod +x "$OUT/install-on-device.sh" "$OUT/apply-network.sh" "$OUT/apply-dns.sh" "$OUT/adblock-ctl.sh" "$OUT/status.sh" "$OUT/stats-ctl.sh" "$OUT/firmware-ctl.sh" "$OUT/leandns-fw-upload" "$OUT/leandns" "$OUT/leandns-discoverd" "$OUT/leandns-discover" "$OUT/leandns-stats"

echo "Staged at: $OUT"
ls -lh "$OUT"
