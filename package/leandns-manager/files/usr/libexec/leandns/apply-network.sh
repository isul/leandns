#!/bin/sh
# Apply LAN changes temporarily and restore the previous UCI values on timeout.
set -eu

PENDING=/etc/leandns/network.pending
VALIDATE=/usr/bin/leandns-validate
WAIT_SECONDS=120
BOOT_ID=/proc/sys/kernel/random/boot_id

log() { logger -t leandns-net "$*"; }
error() { printf '{"ok":false,"error":"%s"}\n' "$1"; }

snapshot() {
	package="$1"
	exported="$(uci export "$package")" || return 1
	# Keep UCI's quoting and list entries when restoring the LAN options.
	printf '%s\n' "$exported" | awk -v package="$package" '
		$1 == "config" { lan = ($3 == "\047lan\047" || $3 == "lan") }
		lan && ($1 == "option" || $1 == "list") {
			action=($1 == "list" ? "add_list" : "set")
			key=$2
			gsub(/\047/, "", key)
			if (key != "ipaddr" && key != "netmask" && key != "gateway" &&
			    !(package == "network" && key == "proto") &&
			    !(package == "leandns" && key == "dns_appliance")) next
			sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "")
			printf "%s %s.lan.%s=%s\n", action, package, key, $0
		}
	'
}

restore() {
	log "restoring previous LAN settings"
	for key in network.lan.proto network.lan.ipaddr network.lan.netmask network.lan.gateway \
		leandns.lan.ipaddr leandns.lan.netmask leandns.lan.gateway leandns.lan.dns_appliance; do
		uci -q delete "$key" || true
	done
	uci -q batch < "$transaction/restore" &&
		uci commit network && uci commit leandns && /etc/init.d/network reload
}

cleanup() {
	# Disarm the journal atomically before deleting its contents.
	finished="$(mktemp -d /etc/leandns/.network-done.XXXXXX)" || return 1
	if mv "$PENDING" "$finished/"; then
		rm -rf "$finished"
	else
		rmdir "$finished"
		return 1
	fi
}

apply() {
	uci -q batch <<-EOF || return 1
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
	/etc/init.d/network reload
}

case "${1:-}" in
	--pending)
		transaction="$(cat "$PENDING/current" 2>/dev/null || true)"
		ip=
		state=
		if [ -n "$transaction" ] && [ -f "$transaction/prepared" ]; then
			ip="$(cat "$transaction/ip" 2>/dev/null || true)"
			state=applying
			[ ! -f "$transaction/ready" ] || state=ready
			[ ! -f "$transaction/restore_failed" ] || state=restore_failed
		fi
		printf '"pending_ip":"%s","pending_state":"%s"\n' "$ip" "$state"
		exit 0
		;;
	--confirm)
		transaction="$(cat "$PENDING/current" 2>/dev/null || true)"
		if [ -z "$transaction" ] || [ ! -f "$transaction/ready" ] || ! mkdir "$transaction/decision" 2>/dev/null; then
			error "확정할 임시 설정이 없거나 아직 적용 중입니다."
			exit 0
		fi
		if ! cleanup; then
			rmdir "$transaction/decision"
			error "임시 설정 확정에 실패했습니다."
			exit 0
		fi
		log "LAN settings confirmed"
		echo '{"ok":true}'
		exit 0
		;;
	--recover)
		[ -d "$PENDING" ] || exit 0
		transaction="$(cat "$PENDING/current" 2>/dev/null || true)"
		if [ -n "$transaction" ] && [ ! -f "$transaction/restore_failed" ] &&
			[ "$(cat "$transaction/boot" 2>/dev/null || true)" = "$(cat "$BOOT_ID")" ]; then
			exit 0
		fi
		if [ -n "$transaction" ] && [ -f "$transaction/prepared" ]; then
			if ! restore; then
				touch "$transaction/restore_failed"
				log "LAN restore after restart failed"
				exit 1
			fi
		fi
		cleanup
		exit
		;;
	--web)
		shift
		;;
	*)
		# Legacy daemons invoke this path only after their own token check.
		if [ "$(uci -q get leandns.main.udp_set_enabled || echo 0)" != 1 ]; then
			error "UDP IP 변경이 비활성화되어 있습니다."
			exit 0
		fi
		;;
esac

ipaddr="${1:-}"
netmask="${2:-}"
gateway="${3:-}"
for address in "$ipaddr" "$netmask" "$gateway"; do
	if ! "$VALIDATE" ipv4 "$address"; then
		error "IP 주소, 서브넷 마스크 및 게이트웨이를 확인하세요."
		exit 0
	fi
done

umask 077
if ! mkdir "$PENDING" 2>/dev/null; then
	error "다른 네트워크 변경이 진행 중입니다."
	exit 0
fi
trap cleanup EXIT
transaction="$(mktemp -d "$PENDING/transaction.XXXXXX")"
printf '%s\n' "$transaction" > "$PENDING/current"
cat "$BOOT_ID" > "$transaction/boot"
snapshot network > "$transaction/restore"
snapshot leandns >> "$transaction/restore"
printf '%s\n' "$ipaddr" > "$transaction/ip"
touch "$transaction/prepared"
(
	trap - EXIT
	sleep 1
	if apply; then
		touch "$transaction/ready"
		sleep "$WAIT_SECONDS"
	else
		log "temporary LAN apply failed"
	fi
	if mkdir "$transaction/decision" 2>/dev/null; then
		if restore; then
			cleanup
		else
			touch "$transaction/restore_failed"
			log "automatic LAN restore failed"
		fi
	fi
) </dev/null >/tmp/leandns-network.log 2>&1 &
trap - EXIT
printf '{"ok":true,"pending_ip":"%s","timeout_s":%s}\n' "$ipaddr" "$WAIT_SECONDS"
