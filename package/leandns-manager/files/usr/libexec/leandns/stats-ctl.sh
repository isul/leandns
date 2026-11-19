#!/bin/sh
# RAM-only DNS block counters + recent ring (cleared on reboot).
# Does not write to flash/overlay. Pause/flush before heavy work.

set -eu

DIR=/tmp/leandns-stats
LOG=/tmp/leandns-dnsmasq-queries.log
PENDING="$DIR/pending"
RECENT="$DIR/recent"
BUCKETS="$DIR/buckets"
META="$DIR/meta"
OFFSET="$DIR/offset"
PAUSE="$DIR/paused"
CHUNK="$DIR/chunk"

mkdir -p "$DIR"

free_ram_kb() {
	awk '/^MemAvailable:/ {print $2; found=1} END {if (!found) print 0}' /proc/meminfo 2>/dev/null || echo 0
}

min_free_ram_kb() {
	v="$(uci -q get leandns.main.min_free_ram_kb 2>/dev/null || true)"
	echo "${v:-8192}"
}

query_log_enabled() {
	[ "$(uci -q get leandns.main.query_log 2>/dev/null || echo 0)" = "1" ]
}

configured_recent_max() {
	v="$(uci -q get leandns.main.query_log_max 2>/dev/null || true)"
	v="${v:-20}"
	case "$v" in
		*[!0-9]*) v=20 ;;
	esac
	[ "$v" -lt 10 ] && v=10
	[ "$v" -gt 20 ] && v=20
	echo "$v"
}

# 20 when headroom exists; 10 near min_free_ram; 0 = pause ingest.
effective_recent_max() {
	ram="$(free_ram_kb)"
	min="$(min_free_ram_kb)"
	want="$(configured_recent_max)"
	hi=$((min + 3072))
	if [ "$ram" -lt "$min" ]; then
		echo 0
		return
	fi
	if [ "$ram" -lt "$hi" ]; then
		echo 10
		return
	fi
	echo "$want"
}

json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

meta_get() {
	key="$1"
	[ -f "$META" ] || { echo ""; return; }
	sed -n "s/^${key}=//p" "$META" | head -n1
}

meta_set() {
	key="$1"
	val="$2"
	tmp="$(mktemp "$DIR/meta.XXXXXX")"
	if [ -f "$META" ]; then
		grep -v "^${key}=" "$META" > "$tmp" || true
	else
		: > "$tmp"
	fi
	printf '%s=%s\n' "$key" "$val" >> "$tmp"
	mv -f "$tmp" "$META"
}

ensure_day() {
	today="$(date +%Y%m%d 2>/dev/null || echo 0)"
	cur="$(meta_get day)"
	[ -n "$cur" ] || cur=0
	if [ "$cur" != "$today" ]; then
		prev="$(meta_get today)"
		prev="${prev:-0}"
		[ "$cur" = "0" ] || meta_set yesterday "$prev"
		meta_set today 0
		meta_set day "$today"
	fi
}

trim_file_lines() {
	file="$1"
	max="$2"
	[ -f "$file" ] || return 0
	[ "$max" -gt 0 ] || { : > "$file"; return 0; }
	lines="$(wc -l < "$file" 2>/dev/null | tr -d ' ')"
	[ -n "$lines" ] || lines=0
	[ "$lines" -le "$max" ] && return 0
	tail -n "$max" "$file" > "$file.tmp" && mv -f "$file.tmp" "$file"
}

classify_domain() {
	d="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
	case "$d" in
		*doubleclick*|*googlesyndication*|*googleadservices*|*adservice*|*adnxs*|*advertising*|*adsystem*|*pagead*|*adclick*|ads.*|*.ads.*|*banner*)
			echo ad ;;
		*analytics*|*tracking*|*telemetry*|*pixel*|*beacon*|*scorecard*|*hotjar*|*mixpanel*)
			echo track ;;
		*)
			echo block ;;
	esac
}

bump_bucket() {
	minute="$1"
	[ -f "$BUCKETS" ] || : > "$BUCKETS"
	tmp="$(mktemp "$DIR/buckets.XXXXXX")"
	found=0
	while IFS=' ' read -r m c || [ -n "${m:-}" ]; do
		[ -n "${m:-}" ] || continue
		if [ "$m" = "$minute" ]; then
			c=$(( ${c:-0} + 1 ))
			found=1
		fi
		printf '%s %s\n' "$m" "${c:-0}" >> "$tmp"
	done < "$BUCKETS"
	[ "$found" = 1 ] || printf '%s 1\n' "$minute" >> "$tmp"
	tail -n 12 "$tmp" > "$BUCKETS"
	rm -f "$tmp"
}

record_pending() {
	domain="$1"
	client="$2"
	printf '%s|%s\n' "$domain" "$client" >> "$PENDING"
	trim_file_lines "$PENDING" 64
}

lookup_pending() {
	domain="$1"
	[ -f "$PENDING" ] || { echo ""; return; }
	awk -F'|' -v d="$domain" '$1 == d { c=$2 } END { print c }' "$PENDING"
}

record_block() {
	domain="$1"
	client="$2"
	limit="$3"
	[ "$limit" -gt 0 ] || return 0
	ensure_day
	now="$(date +%s 2>/dev/null || echo 0)"
	minute=$((now / 60))
	kind="$(classify_domain "$domain")"
	today="$(meta_get today)"
	today="${today:-0}"
	meta_set today $((today + 1))
	meta_set last_ts "$now"
	meta_set last_domain "$domain"
	meta_set last_client "$client"
	bump_bucket "$minute"
	printf '%s|%s|%s|%s\n' "$now" "$domain" "$client" "$kind" >> "$RECENT"
	trim_file_lines "$RECENT" "$limit"
}

truncate_log() {
	: > "$LOG" 2>/dev/null || true
	echo 0 > "$OFFSET"
}

cmd_flush() {
	rm -f "$PENDING" "$RECENT" "$BUCKETS" "$META" "$OFFSET" "$CHUNK" "$DIR"/meta.* "$DIR"/buckets.*
	truncate_log
	mkdir -p "$DIR"
}

cmd_pause() {
	touch "$PAUSE"
	# Stop ingest and shrink RAM buffers; keep log inode so dnsmasq keeps writing.
	rm -f "$PENDING" "$CHUNK"
	trim_file_lines "$RECENT" 10
	# Clear log content in place (do not replace the file).
	if [ -f "$LOG" ]; then
		: > "$LOG"
	fi
	echo 0 > "$OFFSET"
}

cmd_resume() {
	rm -f "$PAUSE"
}

cmd_trim_for_memory() {
	limit="$(effective_recent_max)"
	if [ "$limit" -eq 0 ]; then
		cmd_pause
		return 0
	fi
	trim_file_lines "$RECENT" "$limit"
	if [ -f "$LOG" ]; then
		sz="$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')"
		[ -n "$sz" ] || sz=0
		if [ "$sz" -gt 65536 ]; then
			# Truncate in place (same inode). `mv` would detach dnsmasq's open FD.
			if tail -c 24576 "$LOG" > "$LOG.tmp" 2>/dev/null; then
				cat "$LOG.tmp" > "$LOG"
				rm -f "$LOG.tmp"
				echo 0 > "$OFFSET"
			fi
		fi
	fi
}

ingest_line() {
	line="$1"
	limit="$2"
	# OpenWrt dnsmasq file log examples:
	#   Nov 18 08:36:52 dnsmasq[12251]: 260 192.168.0.200/53097 query[A] ads.example from 192.168.0.200
	#   Nov 18 08:36:52 dnsmasq[12251]: 259 192.168.0.200/49210 config ads.example is NXDOMAIN
	msg="$(printf '%s\n' "$line" | sed -n 's/.*dnsmasq\[[0-9][0-9]*\]: //p')"
	[ -n "$msg" ] || msg="$line"

	# Optional "id client/port " prefix used by OpenWrt dnsmasq.
	id=
	peer=
	rest="$msg"
	case "$msg" in
		[0-9]*\ */*[0-9]*\ *)
			id="${msg%% *}"
			tmp="${msg#* }"
			peer="${tmp%% *}"
			rest="${tmp#* }"
			;;
	esac
	: "$id"

	client_from_peer=
	case "$peer" in
		*/*) client_from_peer="${peer%/*}" ;;
		*) client_from_peer="$peer" ;;
	esac

	case "$rest" in
		query\[*)
			# query[A] example.com from 192.168.1.2
			qrest="${rest#*\] }"
			domain="${qrest%% from *}"
			client="${qrest#* from }"
			domain="$(printf '%s' "$domain" | tr -d ' \t\r\n')"
			client="$(printf '%s' "$client" | tr -d ' \t\r\n')"
			[ -n "$domain" ] || return 0
			case "$client" in
				''|"$qrest") client="${client_from_peer:-—}" ;;
			esac
			record_pending "$domain" "$client"
			;;
		config\ *|cached\ *)
			# Adblock-lean uses local=/domain/ → NXDOMAIN.
			# Do NOT count NODATA: with ipv6_dns=0, AAAA filter logs
			# "config example.com is NODATA" for normal sites.
			case "$rest" in
				*" is NXDOMAIN")
					domain="${rest#* }"
					domain="${domain%% is *}"
					domain="$(printf '%s' "$domain" | tr -d ' \t\r\n')"
					[ -n "$domain" ] || return 0
					client="$(lookup_pending "$domain")"
					[ -n "$client" ] || client="${client_from_peer:-—}"
					record_block "$domain" "$client" "$limit"
					;;
			esac
			;;
	esac
}

cmd_tick() {
	query_log_enabled || return 0
	[ -f "$PAUSE" ] && return 0
	cmd_trim_for_memory
	limit="$(effective_recent_max)"
	[ "$limit" -gt 0 ] || return 0
	ensure_day
	[ -f "$LOG" ] || return 0

	off=0
	[ -f "$OFFSET" ] && off="$(cat "$OFFSET" 2>/dev/null || echo 0)"
	case "$off" in *[!0-9]*) off=0 ;; esac
	size="$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')"
	[ -n "$size" ] || size=0
	[ "$off" -le "$size" ] || off=0
	[ "$size" -gt "$off" ] || return 0

	# Prefer tail byte seek (BusyBox); fall back to dd.
	start=$((off + 1))
	if ! tail -c "+$start" "$LOG" > "$CHUNK" 2>/dev/null; then
		dd if="$LOG" bs=1024 skip=$((off / 1024)) 2>/dev/null | \
			dd bs=1 skip=$((off % 1024)) of="$CHUNK" 2>/dev/null || return 0
	fi
	while IFS= read -r line || [ -n "$line" ]; do
		[ -n "$line" ] || continue
		ingest_line "$line" "$limit"
	done < "$CHUNK"
	rm -f "$CHUNK"
	echo "$size" > "$OFFSET"
}

bucket_count_since() {
	since_min="$1"
	total=0
	[ -f "$BUCKETS" ] || { echo 0; return; }
	while IFS=' ' read -r m c || [ -n "${m:-}" ]; do
		[ -n "${m:-}" ] || continue
		case "$m" in *[!0-9]*) continue ;; esac
		case "$c" in ''|*[!0-9]*) continue ;; esac
		[ "$m" -ge "$since_min" ] || continue
		total=$((total + c))
	done < "$BUCKETS"
	echo "$total"
}

hhmm_from_minute() {
	m="$1"
	epoch=$((m * 60))
	date -d "@$epoch" +%H:%M 2>/dev/null && return 0
	date -r "$epoch" +%H:%M 2>/dev/null && return 0
	# Fallback without GNU/BSD date helpers.
	printf '%02d:%02d' $(((m % 1440) / 60)) $((m % 60))
}

hms_from_ts() {
	ts="$1"
	date -d "@$ts" +%H:%M:%S 2>/dev/null && return 0
	date -r "$ts" +%H:%M:%S 2>/dev/null && return 0
	echo "—"
}

type_label() {
	case "$1" in
		ad) echo ad ;;
		track) echo track ;;
		*) echo block ;;
	esac
}

cmd_json() {
	ensure_day
	enabled=false
	query_log_enabled && enabled=true
	paused=false
	[ -f "$PAUSE" ] && paused=true

	cfg_max="$(configured_recent_max)"
	limit="$(effective_recent_max)"
	if [ "$limit" -le 0 ]; then
		limit=10
	elif [ "$limit" -gt "$cfg_max" ]; then
		limit="$cfg_max"
	fi

	now="$(date +%s 2>/dev/null || echo 0)"
	cur_min=$((now / 60))
	c1="$(bucket_count_since "$cur_min")"
	c10="$(bucket_count_since $((cur_min - 9)))"
	today="$(meta_get today)"; today="${today:-0}"
	yest="$(meta_get yesterday)"; yest="${yest:-0}"
	last_ts="$(meta_get last_ts)"; last_ts="${last_ts:-0}"
	last_domain="$(meta_get last_domain)"
	age=null
	case "$last_ts" in
		''|*[!0-9]*) ;;
		*)
			if [ "$last_ts" -gt 0 ]; then
				age=$((now - last_ts))
				[ "$age" -lt 0 ] && age=0
			fi
			;;
	esac

	printf '{'
	printf '"enabled":%s,' "$enabled"
	printf '"paused":%s,' "$paused"
	printf '"recent_limit":%s,' "$limit"
	printf '"count_1m":%s,' "$c1"
	printf '"count_10m":%s,' "$c10"
	printf '"count_today":%s,' "$today"
	printf '"count_yesterday":%s,' "$yest"
	if [ "$age" = "null" ]; then
		printf '"last_block_age_sec":null,'
	else
		printf '"last_block_age_sec":%s,' "$age"
	fi
	printf '"last_block_domain":"%s",' "$(json_escape "${last_domain:-}")"

	printf '"trend":['
	first=1
	i=9
	while [ "$i" -ge 0 ]; do
		m=$((cur_min - i))
		c=0
		if [ -f "$BUCKETS" ]; then
			c="$(awk -v mm="$m" '$1 == mm { print $2; found=1 } END { if (!found) print 0 }' "$BUCKETS")"
		fi
		# m = unix minute index; UI formats local HH:MM from m*60.
		[ "$first" = 1 ] || printf ','
		first=0
		printf '{"m":%s,"c":%s}' "$m" "$c"
		i=$((i - 1))
	done
	printf '],'

	printf '"recent":['
	first=1
	n=0
	if [ -f "$RECENT" ]; then
		# Newest first into a temp list (avoid pipe subshell for counters).
		# UI formats local time from ts; omit device-local HH:MM:SS.
		awk -F'|' '
			NF >= 4 { a[++n] = $0 }
			END { for (i = n; i >= 1; i--) print a[i] }
		' "$RECENT" | head -n "$limit" > "$DIR/recent.view"
		while IFS='|' read -r ts domain client kind || [ -n "${ts:-}" ]; do
			[ -n "${ts:-}" ] || continue
			n=$((n + 1))
			tl="$(type_label "${kind:-block}")"
			[ "$first" = 1 ] || printf ','
			first=0
			printf '{"n":%s,"domain":"%s","type":"%s","client":"%s","ts":%s}' \
				"$n" "$(json_escape "$domain")" "$(json_escape "$tl")" "$(json_escape "$client")" "$ts"
		done < "$DIR/recent.view"
		rm -f "$DIR/recent.view"
	fi
	printf ']'
	printf '}\n'
}

case "${1:-}" in
	tick) cmd_tick ;;
	flush) cmd_flush ;;
	pause) cmd_pause ;;
	resume) cmd_resume ;;
	trim) cmd_trim_for_memory ;;
	json) cmd_json ;;
	*)
		echo "usage: $0 tick|flush|pause|resume|trim|json" >&2
		exit 2
		;;
esac
