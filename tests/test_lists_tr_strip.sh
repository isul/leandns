#!/usr/bin/env bash
# Regression: BusyBox tr -d '[:space:]' deletes letters a,c,e,s,p.
# lists_set must strip whitespace with an explicit character set instead.
set -euo pipefail

domain='adclick.g.doubleclick.net'

broken="$(printf '%s' "$domain" | busybox tr -d '[:space:]')"
[ "$broken" = 'dlik.g.doubllik.nt' ] || {
	echo "expected busybox class bug, got: [$broken]" >&2
	exit 1
}

fixed="$(printf '%s' "  ${domain}  " | tr -d ' \t\r\n')"
[ "$fixed" = "$domain" ] || {
	echo "whitespace strip corrupted domain: [$fixed]" >&2
	exit 1
}

# Mirror the lists_set parse path used by rpcd/leandns
input='{"allow":[],"block":["adclick.g.doubleclick.net"]}'
block_part="$(printf '%s' "$input" | sed -n 's/.*"block"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p')"
got="$(printf '%s\n' "$block_part" | sed 's/"[[:space:]]*,[[:space:]]*"/\n/g; s/"//g' | while IFS= read -r d; do
	d="$(printf '%s' "$d" | tr -d ' \t\r\n')"
	[ -z "$d" ] && continue
	printf '%s\n' "$d"
done)"
[ "$got" = "$domain" ] || {
	echo "lists_set parse path failed: [$got]" >&2
	exit 1
}

echo 'lists_tr_strip: ok'
