#!/bin/sh
# Collect measurable system/DNS status as JSON. No fabricated metrics.

set -eu

mode="${1:-}"
dns_probe() {
	dns_host="${1:-$(uci -q get leandns.main.dns_test_host 2>/dev/null || true)}"
	dns_host="${dns_host:-one.one.one.one}"
	case "$dns_host" in
		*[!A-Za-z0-9.-]*) dns_host= ;;
	esac
	if ! /usr/bin/leandns-validate domain "$dns_host"; then
		echo '{"ok":false,"error":"Check the domain format."}'
		return
	fi
	dns_ok=unsupported
	dns_lat=null
	addresses=
	if command -v nslookup >/dev/null 2>&1; then
		read -r before _ < /proc/uptime
		dns_ok=false
		answer="$(nslookup -timeout=2 -retry=1 "$dns_host" 127.0.0.1 2>/dev/null)" && dns_ok=true
		read -r after _ < /proc/uptime
		if [ "$dns_ok" = true ]; then
			addresses="$(printf '%s\n' "$answer" | awk '
				/^Name:/ { response=1 }
				response && /^Address( [0-9]+)?:/ {
					if ($1 == "Address:") ip=$2
					else ip=$3
					if (ip ~ /^[0-9a-fA-F:.]+$/ && ip ~ /[.:]/ && !seen[ip]++) {
						printf "%s\"%s\"", sep, ip
						sep=","
					}
				}')"
			[ -n "$addresses" ] || dns_ok=false
		fi
		dns_lat=$(( (${after%.*} - ${before%.*}) * 1000 + (1${after#*.} - 1${before#*.}) * 10 ))
	fi
	printf '{"ok":true,"dns_test_ok":"%s","dns_test_latency_ms":%s,"dns_test_resolution_ms":10,"dns_test_host":"%s","addresses":[%s]}\n' \
		"$dns_ok" "$dns_lat" "$dns_host" "$addresses"
}

if [ "$mode" = "--dns-test" ]; then
	dns_probe "${2:-}"
	exit
fi

read -r mem_total mem_avail <<EOF
$(awk '/^MemTotal:/ {total=$2} /^MemAvailable:/ {avail=$2} END {print total+0, avail=="" ? "null" : avail}' /proc/meminfo)
EOF

cpu_usage() {
	read -r _ u1 n1 s1 i1 _ < /proc/stat
	sleep 1
	read -r _ u2 n2 s2 i2 _ < /proc/stat
	du=$((u2 - u1))
	dn=$((n2 - n1))
	ds=$((s2 - s1))
	di=$((i2 - i1))
	total=$((du + dn + ds + di))
	if [ "$total" -le 0 ]; then
		echo "unsupported"
		return
	fi
	busy=$((du + dn + ds))
	echo $((busy * 100 / total))
}

if [ "$mode" = "--quick" ] || [ "$mode" = "--system" ]; then
	cpu="unsupported"
else
	cpu="$(cpu_usage)"
fi

if grep -q ' /overlay ' /proc/mounts; then
	flash_scope=overlay
	flash_total="$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $2}')"
	flash_free="$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}')"
else
	flash_scope=root
	flash_total="$(df -k / 2>/dev/null | awk 'NR==2 {print $2}')"
	flash_free="$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')"
fi
flash_total="${flash_total:-null}"
flash_free="${flash_free:-null}"

if pidof dnsmasq >/dev/null 2>&1; then
	dnsmasq_running=true
else
	dnsmasq_running=false
fi

uptime_sec="$(awk '{print int($1)}' /proc/uptime)"
cachesize="$(uci -q get leandns.main.cachesize 2>/dev/null || echo 0)"

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

leandns_version="$(tr -d '\r\n' < /etc/leandns/version 2>/dev/null || true)"
leandns_version="${leandns_version:-1.0.1}"
firmware=
if [ -r /etc/openwrt_release ]; then
	# shellcheck disable=SC1091
	. /etc/openwrt_release
	firmware="${DISTRIB_DESCRIPTION:-${DISTRIB_RELEASE:-}}"
fi
[ -n "$firmware" ] || firmware=unsupported

printf '{'
printf '"dnsmasq_running":%s,' "$dnsmasq_running"
printf '"uptime_sec":%s,' "$uptime_sec"
printf '"mem_total_kb":%s,' "$mem_total"
printf '"mem_available_kb":%s,' "$mem_avail"
printf '"cpu_percent":"%s",' "$cpu"
printf '"flash_scope":"%s",' "$flash_scope"
printf '"flash_total_kb":%s,' "$flash_total"
printf '"flash_free_kb":%s,' "$flash_free"
printf '"cachesize":%s,' "${cachesize:-0}"
printf '"version":"%s",' "$(json_escape "$leandns_version")"
printf '"firmware":"%s",' "$(json_escape "$firmware")"
printf '"cache_hit_rate":"unsupported",'
printf '"per_client_stats":"unsupported",'
if [ -x /usr/libexec/leandns/stats-ctl.sh ]; then
	block_stats="$(/usr/libexec/leandns/stats-ctl.sh json 2>/dev/null || echo '{}')"
else
	block_stats='{"enabled":false,"paused":false,"recent_limit":0,"count_1m":0,"count_10m":0,"count_today":0,"count_yesterday":0,"last_block_age_sec":null,"last_block_domain":"","trend":[],"recent":[]}'
fi
# Prefer live today counter when available.
blocked_today="$(printf '%s' "$block_stats" | sed -n 's/.*"count_today"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
if [ -n "$blocked_today" ]; then
	printf '"blocked_query_count":%s,' "$blocked_today"
else
	printf '"blocked_query_count":"unsupported",'
fi
printf '"block_stats":%s,' "$block_stats"
printf '"adblock":'
if [ "$mode" = "--system" ]; then
	printf '{}'
else
	/usr/libexec/leandns/adblock-ctl.sh status 2>/dev/null || printf '{}'
	upstream="$(/usr/libexec/leandns/upstream-list.sh get-json)"
	internal_domain="$(uci -q get leandns.main.internal_domain || true)"
	internal_domain="${internal_domain:-home.arpa}"
	printf ',"upstream":[%s],"internal_domain":"%s"' "$upstream" "$internal_domain"
	probe="$(dns_probe)"
	case "$probe" in
		'{"ok":true,'*)
			probe="${probe#*,}"
			printf ',%s' "${probe%\}}"
			;;
		*) printf ',"dns_test_ok":"unsupported"' ;;
	esac
fi
printf '}\n'
