#!/bin/sh
# Collect measurable system/DNS status as JSON. No fabricated metrics.

set -eu

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

mem_total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
mem_avail="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"

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

if [ "$QUICK" = "1" ]; then
	cpu="unsupported"
else
	cpu="$(cpu_usage)"
fi

if mount 2>/dev/null | grep -q 'on /overlay'; then
	flash_total="$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $2}')"
	flash_free="$(df -k /overlay 2>/dev/null | awk 'NR==2 {print $4}')"
else
	flash_total="$(df -k / 2>/dev/null | awk 'NR==2 {print $2}')"
	flash_free="$(df -k / 2>/dev/null | awk 'NR==2 {print $4}')"
fi
flash_total="${flash_total:-0}"
flash_free="${flash_free:-0}"

if pidof dnsmasq >/dev/null 2>&1; then
	dnsmasq_running=true
else
	dnsmasq_running=false
fi

dns_host="$(uci -q get leandns.main.dns_test_host 2>/dev/null || true)"
dns_host="${dns_host:-one.one.one.one}"
dns_ok="unsupported"
dns_lat="unsupported"
if command -v nslookup >/dev/null 2>&1; then
	t0="$(date +%s 2>/dev/null || echo 0)"
	if nslookup "$dns_host" 127.0.0.1 >/dev/null 2>&1; then
		dns_ok=true
	else
		dns_ok=false
	fi
	t1="$(date +%s 2>/dev/null || echo 0)"
	dns_lat=$(( (t1 - t0) * 1000 ))
fi

uptime_sec="$(awk '{print int($1)}' /proc/uptime)"
cachesize="$(uci -q get leandns.main.cachesize 2>/dev/null || echo 0)"
abl_json="$(/usr/libexec/leandns/adblock-ctl.sh status 2>/dev/null || echo '{}')"

printf '{'
printf '"dnsmasq_running":%s,' "$dnsmasq_running"
printf '"uptime_sec":%s,' "$uptime_sec"
printf '"mem_total_kb":%s,' "$mem_total"
printf '"mem_available_kb":%s,' "$mem_avail"
printf '"cpu_percent":"%s",' "$(json_escape "$cpu")"
printf '"flash_total_kb":%s,' "$flash_total"
printf '"flash_free_kb":%s,' "$flash_free"
printf '"cachesize":%s,' "${cachesize:-0}"
printf '"cache_hit_rate":"unsupported",'
printf '"blocked_query_count":"unsupported",'
printf '"per_client_stats":"unsupported",'
printf '"dns_test_ok":"%s",' "$(json_escape "$dns_ok")"
printf '"dns_test_latency_ms":"%s",' "$(json_escape "$dns_lat")"
printf '"dns_test_host":"%s",' "$(json_escape "$dns_host")"
printf '"adblock":%s' "$abl_json"
printf '}\n'
