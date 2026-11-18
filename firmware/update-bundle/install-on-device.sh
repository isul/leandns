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
chmod +x /usr/libexec/rpcd/leandns /usr/libexec/leandns/apply-network.sh /usr/sbin/leandns-discoverd /etc/init.d/leandns-discover
mkdir -p /etc/leandns
[ -s /etc/leandns/udp.token ] || tr -dc A-Za-z0-9 </dev/urandom | head -c 24 > /etc/leandns/udp.token
chmod 600 /etc/leandns/udp.token
/etc/init.d/leandns-discover enable
/etc/init.d/leandns-discover restart
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
echo OK
