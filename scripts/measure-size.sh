#!/usr/bin/env bash
# Measure artifact sizes available on the build host. Device RAM peaks are N/A.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
METRICS="$ROOT/docs/metrics.md"
METRICS_KO="$ROOT/docs/ko/metrics.md"
"$ROOT/scripts/package.sh" >/dev/null

web_b="$(du -sb "$ROOT/web" | awk '{print $1}')"
pkg_b="$(du -sb "$ROOT/package/leandns-manager/files" | awk '{print $1}')"
fw_note="not built yet"
if compgen -G "$ROOT/firmware/bin/leandns-*-sysupgrade.bin" >/dev/null; then
  fw_note="$(du -h "$ROOT/firmware/bin"/leandns-*-sysupgrade.bin | head -n1 | awk '{print $1, $2}')"
elif compgen -G "$ROOT/firmware/bin/openwrt-*-sysupgrade.bin" >/dev/null; then
  fw_note="$(du -h "$ROOT/firmware/bin"/openwrt-*-sysupgrade.bin | head -n1 | awk '{print $1, $2}')"
elif compgen -G "$ROOT/firmware/openwrt-*-sysupgrade.bin" >/dev/null; then
  fw_note="$(du -h "$ROOT/firmware"/openwrt-*-sysupgrade.bin | awk '{print $1, $2}')"
fi

stamp="$(date -Iseconds)"
host="$(uname -srm)"
mkdir -p "$(dirname "$METRICS_KO")"

cat > "$METRICS" <<EOF
English | [한국어](ko/metrics.md)

# LeanDNS Size & Resource Measurements

Measured (host): ${stamp}  
Host: ${host}

## Measured on host

| Item | Value |
|------|-------|
| Web UI (\`web/\`) | ${web_b} bytes |
| Package files tree | ${pkg_b} bytes |
| Firmware image | ${fw_note} |

## Device-only (not yet measured)

| Item | Status |
|------|--------|
| DNS/management process RSS | Not measured (needs device) |
| Blocklist update peak RAM | Not measured (needs device) |
| Available RAM after boot | Not measured (needs device) |
| Flash overlay free space | Not measured (needs device) |

Do not mark targets as met without measurements. Device items stay incomplete until RT-AC750L verification.
EOF

cat > "$METRICS_KO" <<EOF
[English](../metrics.md) | 한국어

# LeanDNS 크기·리소스 측정

측정일(호스트): ${stamp}  
호스트: ${host}

## 호스트에서 실측됨

| 항목 | 값 |
|------|-----|
| 웹 UI (\`web/\`) | ${web_b} bytes |
| 패키지 files 트리 | ${pkg_b} bytes |
| 펌웨어 이미지 | ${fw_note} |

## 실기에서만 측정 가능 (미측정)

| 항목 | 상태 |
|------|------|
| DNS/관리 프로세스 RSS | 측정 불가 (실기 필요) |
| 차단목록 업데이트 peak RAM | 측정 불가 (실기 필요) |
| 부팅 후 가용 RAM | 측정 불가 (실기 필요) |
| Flash overlay 여유 | 측정 불가 (실기 필요) |

임의로 목표 달성을 표시하지 않는다. RT-AC750L 검증 전까지 실기 항목은 미완료로 둔다.
EOF

echo "Wrote $METRICS"
echo "Wrote $METRICS_KO"
cat "$METRICS"
