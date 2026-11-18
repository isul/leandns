#!/bin/sh
# Apply LeanDNS LAN IP/netmask/gateway with backup/rollback.
set -eu

BACKUP_DIR=/var/lib/leandns/backup
VALIDATE=/usr/bin/leandns-validate
mkdir -p "$BACKUP_DIR"

log() { logger -t leandns-net "$*"; }

backup() {
	cp -a /etc/config/network "$BACKUP_DIR/network" 2>/dev/null || true
	cp -a /etc/config/leandns "$BACKUP_DIR/leandns-net" 2>/dev/null || true
}

restore() {
	log "rolling back network"
	[ -f "$BACKUP_DIR/network" ] && cp -a "$BACKUP_DIR/network" /etc/config/network
	[ -f "$BACKUP_DIR/leandns-net" ] && cp -a "$BACKUP_DIR/leandns-net" /etc/config/leandns
	uci commit network 2>/dev/null || true
	uci commit leandns 2>/dev/null || true
	/etc/init.d/network reload >/dev/null 2>&1 || true
}

ipaddr="${1:-}"
netmask="${2:-}"
gateway="${3:-}"

[ -n "$ipaddr" ] && [ -n "$netmask" ] && [ -n "$gateway" ] || {
	echo '{"ok":false,"error":"usage: apply-network.sh <ip> <netmask> <gateway>"}'
	exit 2
}

"$VALIDATE" ipv4 "$ipaddr" || { echo '{"ok":false,"error":"invalid ip"}'; exit 1; }
"$VALIDATE" ipv4 "$netmask" || { echo '{"ok":false,"error":"invalid netmask"}'; exit 1; }
"$VALIDATE" ipv4 "$gateway" || { echo '{"ok":false,"error":"invalid gateway"}'; exit 1; }

backup
uci -q batch <<-EOF
	set network.lan.proto='static'
	set network.lan.ipaddr='$ipaddr'
	set network.lan.netmask='$netmask'
	set network.lan.gateway='$gateway'
	set leandns.lan.ipaddr='$ipaddr'
	set leandns.lan.netmask='$netmask'
	set leandns.lan.gateway='$gateway'
	set leandns.lan.dns_appliance='1'
	commit network
	commit leandns
EOF

if /etc/init.d/network reload >/dev/null 2>&1; then
	log "network applied $ipaddr/$netmask gw $gateway"
	echo '{"ok":true,"ipaddr":"'"$ipaddr"'","netmask":"'"$netmask"'","gateway":"'"$gateway"'"}'
else
	restore
	echo '{"ok":false,"error":"network reload failed; rolled back"}'
	exit 1
fi
