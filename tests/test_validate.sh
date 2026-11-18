#!/usr/bin/env bash
# Unit tests for leandns-validate
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="$ROOT/package/leandns-manager/files/usr/bin/leandns-validate"
chmod +x "$V"

pass=0
fail=0
assert_ok() {
  if "$V" "$@"; then pass=$((pass+1)); else echo "FAIL ok: $*"; fail=$((fail+1)); fi
}
assert_bad() {
  if "$V" "$@" 2>/dev/null; then echo "FAIL bad: $*"; fail=$((fail+1)); else pass=$((pass+1)); fi
}

assert_ok domain home.arpa
assert_ok domain nas.home.arpa
assert_ok domain example.com
assert_bad domain ''
assert_bad domain '.bad'
assert_bad domain 'has space.com'
assert_bad domain 'a..b.com'

assert_ok ipv4 192.168.0.1
assert_ok ipv4 8.8.8.8
assert_bad ipv4 999.1.1.1
assert_bad ipv4 1.2.3
assert_bad ipv4 abc

assert_ok hostrecord nas.home.arpa 192.168.0.201
assert_bad hostrecord 'bad domain' 1.2.3.4
assert_bad hostrecord nas.home.arpa 999.0.0.1

assert_ok cachesize 0
assert_ok cachesize 1000
assert_ok cachesize 10000
assert_bad cachesize -1
assert_bad cachesize 10001

assert_ok upstream 1.1.1.1
assert_ok upstream 1.1.1.1#53
assert_ok upstream dns.google
assert_bad upstream 1.1.1.1#99999

echo "validate: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
