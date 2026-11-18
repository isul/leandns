#!/bin/sh
# Read/write LeanDNS upstream DNS list (one server per line).
# File is the source of truth; UCI list is kept in sync when possible.

UPSTREAM_FILE=/etc/leandns/upstream.list
VALIDATE=/usr/bin/leandns-validate

mkdir -p /etc/leandns

cmd_get_json() {
	ups=""
	first=1
	if [ -f "$UPSTREAM_FILE" ]; then
		while IFS= read -r srv || [ -n "$srv" ]; do
			case "$srv" in ''|\#*) continue ;; esac
			[ "$first" = 1 ] || ups="$ups,"
			first=0
			ups="$ups\"$srv\""
		done < "$UPSTREAM_FILE"
	fi
	# Fallback to UCI if file empty
	if [ "$first" = 1 ]; then
		idx=0
		while uci -q get "leandns.main.upstream[$idx]" >/dev/null 2>&1; do
			srv="$(uci -q get "leandns.main.upstream[$idx]")"
			[ "$first" = 1 ] || ups="$ups,"
			first=0
			ups="$ups\"$srv\""
			idx=$((idx + 1))
		done
	fi
	printf '%s' "$ups"
}

cmd_set_from_lines() {
	# stdin: one upstream per line
	tmp="$(mktemp)"
	valid=0
	while IFS= read -r srv || [ -n "$srv" ]; do
		srv="$(printf '%s' "$srv" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		[ -z "$srv" ] && continue
		"$VALIDATE" upstream "$srv" || continue
		printf '%s\n' "$srv" >> "$tmp"
		valid=$((valid + 1))
	done
	# Deduplicate preserve order
	if [ -s "$tmp" ]; then
		awk '!seen[$0]++' "$tmp" > "$UPSTREAM_FILE"
	else
		: > "$UPSTREAM_FILE"
	fi
	rm -f "$tmp"

	# Sync UCI list (best-effort)
	uci -q delete leandns.main.upstream
	while IFS= read -r srv || [ -n "$srv" ]; do
		[ -z "$srv" ] && continue
		uci -q add_list leandns.main.upstream="$srv"
	done < "$UPSTREAM_FILE"
	uci commit leandns
	echo "$valid"
}

cmd_apply_to_dnsmasq() {
	uci -q delete dhcp.@dnsmasq[0].server
	count=0
	if [ -f "$UPSTREAM_FILE" ]; then
		while IFS= read -r srv || [ -n "$srv" ]; do
			case "$srv" in ''|\#*) continue ;; esac
			"$VALIDATE" upstream "$srv" || return 1
			uci -q add_list dhcp.@dnsmasq[0].server="$srv"
			count=$((count + 1))
		done < "$UPSTREAM_FILE"
	fi
	# If file missing, try UCI
	if [ "$count" -eq 0 ]; then
		idx=0
		while uci -q get "leandns.main.upstream[$idx]" >/dev/null 2>&1; do
			srv="$(uci -q get "leandns.main.upstream[$idx]")"
			"$VALIDATE" upstream "$srv" || return 1
			uci -q add_list dhcp.@dnsmasq[0].server="$srv"
			count=$((count + 1))
			idx=$((idx + 1))
		done
	fi
	return 0
}

case "${1:-}" in
	get-json) cmd_get_json ;;
	set-lines) cmd_set_from_lines ;;
	apply-dnsmasq) cmd_apply_to_dnsmasq ;;
	*)
		echo "usage: $0 get-json|set-lines|apply-dnsmasq" >&2
		exit 2
		;;
esac
