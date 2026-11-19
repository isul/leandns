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
UPDATE_FILE=/var/lib/leandns/adblock.update
UPDATE_LOCK=/var/lib/leandns/adblock.update.lock

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
	min_ram="$(uci -q get leandns.main.min_free_ram_kb || true)"
	min_tmp="$(uci -q get leandns.main.min_tmp_kb || true)"
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
	[ -x "$ABL_INIT" ]
}

count_rules() {
	file="$1"
	[ -r "$file" ] || return 1
	# BusyBox may lack `stat -c`; size + mtime is enough for a cache key.
	size="$(wc -c < "$file" 2>/dev/null | tr -d ' \t')"
	mtime="$(date -r "$file" +%s 2>/dev/null || echo 0)"
	key="${size}:${mtime}"
	[ -n "$size" ] || return 1
	if [ -r /var/lib/leandns/adblock.count ] && read -r cached count < /var/lib/leandns/adblock.count &&
		[ "$cached" = "$key" ] && [ -n "$count" ]; then
		printf '%s' "$count"
		return
	fi
	case "$file" in
		*.gz) cmd="gzip -dc" ;;
		*.zst) cmd="zstd -dc" ;;
		*) cmd=cat ;;
	esac
	count="$($cmd "$file" 2>/dev/null | awk -F / '
		/^(server|local)=\// && !/adblocklean-test123\.totallybogus/ { count += NF - 2 }
		END { if (count) print count }
	')"
	if [ -n "$count" ]; then
		mkdir -p /var/lib/leandns
		printf '%s %s\n' "$key" "$count" > /var/lib/leandns/adblock.count
		printf '%s' "$count"
	fi
}

cmd_status() {
	enabled="$(uci -q get leandns.main.enabled || echo 0)"
	abl=missing
	engine=missing
	list=not_applied
	rules=unsupported
	last_update=unsupported
	status="$(cat "$STATUS_FILE" 2>/dev/null || echo unknown)"
	update="$(cat "$UPDATE_FILE" 2>/dev/null || true)"
	case "$update" in
		success|low_ram|low_tmp|failed|updating) ;;
		*) update=unknown ;;
	esac

	if abl_available; then
		if "$ABL_INIT" enabled >/dev/null 2>&1; then abl=enabled; else abl=disabled; fi
		engine=stopped
		pid="$(cat /tmp/adblock-lean/adblock-lean.pid 2>/dev/null || true)"
		case "$pid" in ''|*[!0-9]*) pid= ;; esac
		confdir="$(uci -q get dhcp.@dnsmasq[0].confdir || echo /tmp/dnsmasq.d)"
		if [ -d "$UPDATE_LOCK" ] || { [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; }; then
			engine=checking
			list=updating
		else
			[ "$enabled" != 1 ] || engine=error
			for active in "$confdir"/abl-blocklist "$confdir"/abl-conf-script; do
				[ -f "$active" ] || continue
				if ! command -v nslookup >/dev/null 2>&1; then
					engine=checking
					list=unknown
				elif nslookup -type=A -timeout=1 -retry=1 adblocklean-test123.totallybogus 127.0.0.1 2>/dev/null |
					grep -qE '^Address( [0-9]+)?:[[:space:]]+0\.0\.0\.0([[:space:]]|$)'; then
					engine=ok
					list=applied
					source="$active"
					for shared in /var/run/adblock-lean/abl-blocklist.gz /var/run/adblock-lean/abl-blocklist.zst; do
						[ -s "$shared" ] || continue
						source="$shared"
						break
					done
					last_update="$(date -u -r "$source" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unsupported)"
					rules="$(count_rules "$source" || true)"
					rules="${rules:-unsupported}"
				fi
				break
			done
		fi
	fi
	# A failed wrapper may be killed before it can publish its result.
	[ "$update" != updating ] || [ "$list" = updating ] || update=failed
	case "$status" in updating|ok:*|error:*) ;; *) status=unknown ;; esac
	printf '{"adblock_available":%s,"adblock_state":"%s","leandns_enabled":"%s","rule_count":"%s","last_update":"%s","status_file":"%s","engine_state":"%s","list_state":"%s","update_result":"%s"}\n' \
		"$(abl_available && echo true || echo false)" "$abl" "$enabled" "$rules" "$last_update" "$status" "$engine" "$list" "$update"
}

start_update() {
	action="$1"
	mkdir "$UPDATE_LOCK" 2>/dev/null || {
		echo '{"ok":false,"error":"A list operation is already in progress."}'
		return
	}
	if ! check_resources; then
		if [ "$action" = update ]; then
			sed 's/^error://' "$STATUS_FILE" > "$UPDATE_FILE"
		fi
		rmdir "$UPDATE_LOCK"
		echo '{"ok":false,"error":"Not enough RAM or temporary space for update."}'
		return
	fi
	if [ "$action" = enable ] && ! (
		"$ABL_INIT" enable >/dev/null 2>&1 &&
		uci -q set leandns.main.enabled=1 &&
		uci -q commit leandns
	); then
		rmdir "$UPDATE_LOCK"
		echo '{"ok":false,"error":"Failed to enable ad blocking"}'
		return
	fi
	write_status updating
	[ "$action" != update ] || echo updating > "$UPDATE_FILE"
	# Free tmpfs / shrink stats before list download·process peak RAM.
	[ -x /usr/libexec/leandns/stats-ctl.sh ] && /usr/libexec/leandns/stats-ctl.sh pause >/dev/null 2>&1 || true
	(
		trap 'rmdir "$UPDATE_LOCK"; [ -x /usr/libexec/leandns/stats-ctl.sh ] && /usr/libexec/leandns/stats-ctl.sh resume >/dev/null 2>&1 || true' EXIT
		if (ensure_dnsmasq_confdir && ensure_mini_config && sync_custom_lists) && "$ABL_INIT" start; then
			write_status "ok:$action"
			[ "$action" != update ] || echo success > "$UPDATE_FILE"
		else
			write_status "error:${action}_failed"
			[ "$action" != update ] || echo failed > "$UPDATE_FILE"
			log "adblock start failed; see system logs"
		fi
	) </dev/null >/tmp/leandns-adblock-start.log 2>&1 &
	echo '{"ok":true,"started":"background"}'
}

cmd_enable() {
	if ! abl_available; then
		write_status "error:adblock_lean_missing"
		echo '{"ok":false,"error":"adblock-lean not installed"}'
		return 1
	fi
	start_update enable
}

cmd_disable() {
	mkdir "$UPDATE_LOCK" 2>/dev/null || {
		echo '{"ok":false,"error":"A list operation is already in progress."}'
		return
	}
	trap 'rmdir "$UPDATE_LOCK"' EXIT
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
	if ! abl_available || [ "$(uci -q get leandns.main.enabled || echo 0)" != 1 ]; then
		echo '{"ok":false,"error":"Enable ad blocking first."}'
		return
	fi
	start_update update
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
