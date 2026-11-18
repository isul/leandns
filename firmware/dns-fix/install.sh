#!/bin/sh
set -e
D="${1:-/tmp/dns-fix}"
cp -a "$D/leandns" /usr/libexec/rpcd/leandns
cp -a "$D/upstream-list.sh" /usr/libexec/leandns/upstream-list.sh
cp -a "$D/apply-dns.sh" /usr/libexec/leandns/apply-dns.sh
chmod +x /usr/libexec/rpcd/leandns /usr/libexec/leandns/upstream-list.sh /usr/libexec/leandns/apply-dns.sh
mkdir -p /etc/leandns
[ -s /etc/leandns/upstream.list ] || cp -a "$D/upstream.list" /etc/leandns/upstream.list
/etc/init.d/rpcd restart
/usr/libexec/leandns/apply-dns.sh --apply || true
echo "OK: try DNS settings save again; check: cat /etc/leandns/upstream.list"
