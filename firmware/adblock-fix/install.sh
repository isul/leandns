#!/bin/sh
set -e
D="${1:-/tmp/adblock-fix}"

mkdir -p /usr/lib/adblock-lean /etc/adblock-lean /tmp/dnsmasq.d /usr/libexec/leandns

cp -a "$D/etc/init.d/adblock-lean" /etc/init.d/adblock-lean
cp -a "$D/usr/lib/adblock-lean/"*.sh /usr/lib/adblock-lean/
cp -a "$D/usr/libexec/leandns/adblock-ctl.sh" /usr/libexec/leandns/adblock-ctl.sh
chmod +x /etc/init.d/adblock-lean /usr/libexec/leandns/adblock-ctl.sh

cp -a "$D/etc/adblock-lean/config.mini" /etc/adblock-lean/config.mini
# Do not clobber a working full config; replace stubs only
if [ ! -f /etc/adblock-lean/config ] || ! grep -q 'DNSMASQ_INDEXES=' /etc/adblock-lean/config 2>/dev/null; then
  cp -a "$D/etc/adblock-lean/config" /etc/adblock-lean/config
fi

# Ensure dnsmasq confdir for blocklist drop-in
if ! uci -q get dhcp.@dnsmasq[0].confdir >/dev/null 2>&1; then
  uci -q set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
  uci -q commit dhcp
  /etc/init.d/dnsmasq restart || true
fi

/etc/init.d/adblock-lean enable || true
echo "Installed. Enable from Web UI, or run:"
echo "  /usr/libexec/leandns/adblock-ctl.sh enable"
echo "First list download needs internet and may take a few minutes."
