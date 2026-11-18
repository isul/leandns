#!/usr/bin/env bash
# Host-side smoke test for stats-ctl ingest/json (uses a temp DIR/LOG).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/package/leandns-manager/files/usr/libexec/leandns/stats-ctl.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stub uci + meminfo for host runs.
mkdir -p "$TMP/bin" "$TMP/proc"
cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
case "$*" in
  *query_log_max*) echo 20 ;;
  *query_log*) echo 1 ;;
  *min_free_ram_kb*) echo 1000 ;;
  *) echo "" ;;
esac
EOF
chmod +x "$TMP/bin/uci"
printf 'MemAvailable:    20000 kB\n' > "$TMP/proc/meminfo"

# Rewrite paths inside a working copy.
WORKDIR="$TMP/work"
mkdir -p "$WORKDIR"
sed \
  -e "s#DIR=/tmp/leandns-stats#DIR=$TMP/stats#" \
  -e "s#LOG=/tmp/leandns-dnsmasq-queries.log#LOG=$TMP/queries.log#" \
  -e "s#/proc/meminfo#$TMP/proc/meminfo#g" \
  "$SRC" > "$WORKDIR/stats-ctl.sh"
chmod +x "$WORKDIR/stats-ctl.sh"

export PATH="$TMP/bin:$PATH"

# Real OpenWrt dnsmasq log shape (id + client/port prefix).
# Include AAAA NODATA (ipv6 filter) to ensure it is NOT counted as a block.
cat > "$TMP/queries.log" <<'EOF'
Nov 18 08:36:52 dnsmasq[12251]: 258 192.168.0.200/49210 query[A] googleads.g.doubleclick.net from 192.168.0.200
Nov 18 08:36:52 dnsmasq[12251]: 258 192.168.0.200/49210 config googleads.g.doubleclick.net is NXDOMAIN
Nov 18 08:36:52 dnsmasq[12251]: 259 192.168.0.200/53097 query[A] analytics.twitter.com from 192.168.0.200
Nov 18 08:36:52 dnsmasq[12251]: 259 192.168.0.200/53097 config analytics.twitter.com is NXDOMAIN
Nov 18 08:36:52 dnsmasq[12251]: 260 192.168.1.45/46163 query[AAAA] ads.yahoo.com from 192.168.1.45
Nov 18 08:36:52 dnsmasq[12251]: 260 192.168.1.45/46163 cached ads.yahoo.com is NXDOMAIN
Nov 18 08:36:52 dnsmasq[12251]: 261 192.168.0.200/45005 query[AAAA] api2direct.cursor.sh from 192.168.0.200
Nov 18 08:36:52 dnsmasq[12251]: 261 192.168.0.200/45005 config api2direct.cursor.sh is NODATA
Nov 18 08:36:52 dnsmasq[12251]: 262 127.0.0.1/49155 query[AAAA] one.one.one.one from 127.0.0.1
Nov 18 08:36:52 dnsmasq[12251]: 262 127.0.0.1/49155 config one.one.one.one is NODATA
EOF

"$WORKDIR/stats-ctl.sh" tick
json="$("$WORKDIR/stats-ctl.sh" json)"
echo "$json" | grep -q '"count_today":3' || { echo "FAIL count_today"; echo "$json"; exit 1; }
echo "$json" | grep -q 'googleads.g.doubleclick.net' || { echo "FAIL recent domain"; echo "$json"; exit 1; }
echo "$json" | grep -q '"type":"광고"' || { echo "FAIL type ad"; echo "$json"; exit 1; }
echo "$json" | grep -q '"type":"추적"' || { echo "FAIL type track"; echo "$json"; exit 1; }
echo "$json" | grep -q '192.168.0.200' || { echo "FAIL client"; echo "$json"; exit 1; }
echo "$json" | grep -q '"m":' || { echo "FAIL trend minute epoch"; echo "$json"; exit 1; }
echo "$json" | grep -q 'api2direct.cursor.sh' && { echo "FAIL counted AAAA NODATA"; echo "$json"; exit 1; }
echo "$json" | grep -q 'one.one.one.one' && { echo "FAIL counted dns-test NODATA"; echo "$json"; exit 1; }

"$WORKDIR/stats-ctl.sh" pause
"$WORKDIR/stats-ctl.sh" tick
json2="$("$WORKDIR/stats-ctl.sh" json)"
echo "$json2" | grep -q '"paused":true' || { echo "FAIL paused"; echo "$json2"; exit 1; }

"$WORKDIR/stats-ctl.sh" flush
json3="$("$WORKDIR/stats-ctl.sh" json)"
echo "$json3" | grep -q '"count_today":0' || { echo "FAIL flush"; echo "$json3"; exit 1; }

echo "ok: stats-ctl ingest/json/pause/flush"
