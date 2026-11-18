#!/usr/bin/env bash
# Duplicate rule handling mirrors adblock-ctl sync sorting
set -euo pipefail
tmp="$(mktemp)"
printf '%s\n' 'ads.example.test' 'ads.example.test' 'tracker.test' '' '# comment' 'ads.example.test' > "$tmp"
out="$(grep -v '^#' "$tmp" | grep -v '^$' | sort -u | tr '\n' ' ')"
expected="ads.example.test tracker.test "
[ "$out" = "$expected" ] || { echo "dedupe fail: [$out]"; exit 1; }
rm -f "$tmp"
echo "lists_dedupe: ok"
