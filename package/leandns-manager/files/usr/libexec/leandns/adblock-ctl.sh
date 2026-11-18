#!/bin/sh
# Controlled wrapper around adblock-lean. No arbitrary commands.

set -eu

VALIDATE=/usr/bin/leandns-validate
ALLOW=/etc/leandns/allow.list
BLOCK=/etc/leandns/block.list
ABL_INIT=/etc/init.d/adblock-lean
ABL_CONFIG=/etc/adblock-lean/config
ABL_MINI_TEMPLATE=/etc/adblock-lean/config.mini
STATUS_FILE=/var/lib/leandns/adblock.status

mkdir -p /var/lib/leandns /etc/leandns /etc/adblock-lean /tmp/dnsmasq.d

log() {
	logger -t leandns-adblock "$*"
}

write_status() {
	printf '%s\n' "$1" > "$STATUS_FILE"
}

free_ram_kb() {
	awk '/^MemAvailable:/ {print $2; found=1} END {if (!found) print 0}' /proc/meminfo 2>/dev/null || echo 0
}

tmp_free_kb() {
	df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo 0
}

check_resources() {
	min_ram="$(uci -q get leandns.main.min_free_ram_kb)"
	min_tmp="$(uci -q get leandns.main.min_tmp_kb)"
	min_ram="${min_ram:-8192}"
	min_tmp="${min_tmp:-2048}"
	ram="$(free_ram_kb)"
	tmp="$(tmp_free_kb)"
	if [ "$ram" -lt "$min_ram" ]; then
		log "abort update: free RAM ${ram}KB < ${min_ram}KB"
		write_status "error:low_ram"
		return 1
	fi
	if [ "$tmp" -lt "$min_tmp" ]; then
		log "abort update: /tmp free ${tmp}KB < ${min_tmp}KB"
		write_status "error:low_tmp"
		return 1
	fi
	return 0
}

ensure_dnsmasq_confdir() {
	mkdir -p /tmp/dnsmasq.d
	cur="$(uci -q get dhcp.@dnsmasq[0].confdir || true)"
	if [ -z "$cur" ]; then
		uci -q set dhcp.@dnsmasq[0].confdir='/tmp/dnsmasq.d'
		uci -q commit dhcp
	fi
}

write_mini_config() {
	# Prefer packaged template; fall back to embedded Mini preset.
	if [ -f "$ABL_MINI_TEMPLATE" ]; then
		cp -a "$ABL_MINI_TEMPLATE" "$ABL_CONFIG"
		return 0
	fi
	cat > "$ABL_CONFIG" <<'EOF'
# adblock-lean configuration options
# config_format=v11
# LeanDNS Mini preset (64MB RAM)

whitelist_mode="0"
raw_block_lists="hagezi:pro.mini"
raw_allow_lists=""
raw_ipv4_block_lists=""
dnsmasq_block_lists=""
dnsmasq_allow_lists=""
dnsmasq_ipv4_block_lists=""
hosts_block_lists=""
local_allowlist_path="/etc/leandns/allow.list"
local_blocklist_path="/etc/leandns/block.list"
test_domains="google.com microsoft.com amazon.com"
list_part_failed_action="SKIP"
max_download_retries="3"
hagezi_default_mirror="github"
oisd_default_mirror="oisd"
stevenblack_default_mirror="github"
min_good_line_count="24000"
min_blocklist_part_line_count="1"
min_ipv4_blocklist_part_line_count="1"
min_allowlist_part_line_count="1"
max_file_part_size_KB="2000"
max_blocklist_file_size_KB="2000"
deduplication="1"
compression_util="gzip"
intermediate_compression_options="-3"
final_compression_options="-6"
unload_blocklist_before_update="auto"
boot_start_delay_s="120"
MAX_PARALLEL_JOBS="auto"
custom_script=""
cron_schedule="0 5 * * *"
DNSMASQ_INDEXES="0"
DNSMASQ_CONF_DIRS="/tmp/dnsmasq.d"
EOF
}

ensure_mini_config() {
	[ -d /etc/adblock-lean ] || mkdir -p /etc/adblock-lean
	if [ ! -f "$ABL_CONFIG" ]; then
		write_mini_config
		return 0
	fi
	# Upgrade incomplete LeanDNS stub configs (pre-bundle) to full Mini preset
	if ! grep -q 'DNSMASQ_INDEXES=' "$ABL_CONFIG" 2>/dev/null; then
		log "replacing incomplete adblock-lean config with Mini preset"
		write_mini_config
	fi
}

sync_custom_lists() {
	tmpa="$(mktemp)"
	tmpb="$(mktemp)"
	trap 'rm -f "$tmpa" "$tmpb"' EXIT

	: > "$tmpa"
	: > "$tmpb"

	if [ -f "$ALLOW" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			case "$line" in ''|\#*) continue ;; esac
			d="$(echo "$line" | tr -d '\r' | awk '{print $1}')"
			"$VALIDATE" domain "$d" || continue
			printf '%s\n' "$d" >> "$tmpa"
		done < "$ALLOW"
	fi
	sort -u "$tmpa" -o "$tmpa" 2>/dev/null || true
	cp "$tmpa" "$ALLOW"

	if [ -f "$BLOCK" ]; then
		while IFS= read -r line || [ -n "$line" ]; do
			case "$line" in ''|\#*) continue ;; esac
			d="$(echo "$line" | tr -d '\r' | awk '{print $1}')"
			"$VALIDATE" domain "$d" || continue
			printf '%s\n' "$d" >> "$tmpb"
		done < "$BLOCK"
	fi
	sort -u "$tmpb" -o "$tmpb" 2>/dev/null || true
	cp "$tmpb" "$BLOCK"

	# Keep allow/block paths pointing at LeanDNS lists
	if [ -f "$ABL_CONFIG" ]; then
		if grep -q '^local_allowlist_path=' "$ABL_CONFIG" 2>/dev/null; then
			sed -i 's|^local_allowlist_path=.*|local_allowlist_path="/etc/leandns/allow.list"|' "$ABL_CONFIG"
			sed -i 's|^local_blocklist_path=.*|local_blocklist_path="/etc/leandns/block.list"|' "$ABL_CONFIG"
		else
			printf '\nlocal_allowlist_path="/etc/leandns/allow.list"\n' >> "$ABL_CONFIG"
			printf 'local_blocklist_path="/etc/leandns/block.list"\n' >> "$ABL_CONFIG"
		fi
	fi
}

abl_available() {
	[ -x "$ABL_INIT" ] || [ -f "$ABL_INIT" ]
}

cmd_status() {
	enabled="$(uci -q get leandns.main.enabled)"
	abl="missing"
	rules="unsupported"
	last_update="unsupported"
	if abl_available; then
		if "$ABL_INIT" enabled >/dev/null 2>&1; then
			abl="enabled"
		else
			abl="disabled"
		fi
		for f in /var/run/adblock-lean/abl-blocklist.gz /tmp/adblock-lean/blocklist \
			/tmp/dnsmasq.d/abl-blocklist /tmp/dnsmasq.d/adblock-lean \
			/var/run/adblock-lean/blocklist; do
			if [ -f "$f" ]; then
				case "$f" in
					*.gz)
						rules="$(gzip -dc "$f" 2>/dev/null | grep -c . || echo 0)"
						;;
					*)
						rules="$(grep -c . "$f" 2>/dev/null || echo 0)"
						;;
				esac
				break
			fi
		done
		if [ -f /etc/adblock-lean/config ]; then
			last_update="$(date -r /etc/adblock-lean/config '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo unknown)"
		fi
		[ -f /var/run/adblock-lean/update_time ] && last_update="$(cat /var/run/adblock-lean/update_time)"
	fi
	printf '{"adblock_available":%s,"adblock_state":"%s","leandns_enabled":"%s","rule_count":"%s","last_update":"%s","status_file":"%s"}\n' \
		"$(abl_available && echo true || echo false)" \
		"$abl" "${enabled:-0}" "$rules" "$last_update" "$(cat "$STATUS_FILE" 2>/dev/null || echo ok)"
}

cmd_enable() {
	ensure_dnsmasq_confdir
	ensure_mini_config
	sync_custom_lists
	if ! abl_available; then
		write_status "error:adblock_lean_missing"
		echo '{"ok":false,"error":"adblock-lean not installed"}'
		return 1
	fi
	chmod +x "$ABL_INIT" 2>/dev/null || true
	"$ABL_INIT" enable >/dev/null 2>&1 || true
	uci -q set leandns.main.enabled='1'
	uci -q commit leandns
	# First start downloads Mini list (can take minutes) — do not block rpcd/UI
	write_status "updating"
	(
		if "$ABL_INIT" start >/tmp/leandns-adblock-start.log 2>&1; then
			mkdir -p /var/run/adblock-lean
			date '+%Y-%m-%dT%H:%M:%S' > /var/run/adblock-lean/update_time
			write_status "ok:enabled"
		else
			write_status "error:start_failed"
			log "start failed; see /tmp/leandns-adblock-start.log"
		fi
	) &
	echo '{"ok":true,"started":"background","note":"list download may take a few minutes"}'
}

cmd_disable() {
	if abl_available; then
		"$ABL_INIT" stop >/dev/null 2>&1 || true
		"$ABL_INIT" disable >/dev/null 2>&1 || true
	fi
	uci -q set leandns.main.enabled='0'
	uci -q commit leandns
	write_status "ok:disabled"
	echo '{"ok":true}'
}

cmd_update() {
	if ! abl_available; then
		write_status "error:adblock_lean_missing"
		echo '{"ok":false,"error":"adblock-lean not installed"}'
		return 1
	fi
	check_resources || {
		echo '{"ok":false,"error":"insufficient resources"}'
		return 1
	}
	ensure_dnsmasq_confdir
	ensure_mini_config
	sync_custom_lists
	write_status "updating"
	if "$ABL_INIT" start; then
		mkdir -p /var/run/adblock-lean
		date '+%Y-%m-%dT%H:%M:%S' > /var/run/adblock-lean/update_time
		write_status "ok:updated"
		echo '{"ok":true}'
	else
		write_status "error:update_failed"
		echo '{"ok":false,"error":"update failed; previous list retained"}'
		return 1
	fi
}

cmd_sync_lists() {
	sync_custom_lists
	echo '{"ok":true}'
}

case "${1:-}" in
	status) cmd_status ;;
	enable) cmd_enable ;;
	disable) cmd_disable ;;
	update) cmd_update ;;
	sync-lists) cmd_sync_lists ;;
	*)
		echo "usage: $0 status|enable|disable|update|sync-lists" >&2
		exit 2
		;;
esac
