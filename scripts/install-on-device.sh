#!/usr/bin/env bash
# Install LeanDNS package files onto a reachable OpenWrt device via SSH.
# Does NOT flash firmware. Requires user-provided host.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-}"
if [ -z "$HOST" ]; then
  echo "usage: $0 <user@host>" >&2
  echo "Example (Windows 11 OpenSSH): $0 root@192.168.0.250" >&2
  exit 2
fi

"$ROOT/scripts/package.sh"
STAGE="$ROOT/firmware/leandns-manager-files"

echo "==> Backing up remote configs"
ssh "$HOST" 'mkdir -p /root/leandns-preinstall-backup; cp -a /etc/config/dhcp /etc/config/network /root/leandns-preinstall-backup/ 2>/dev/null || true'

echo "==> Copying files"
scp -r "$STAGE"/* "$HOST":/

echo "==> Fix permissions & restart services"
ssh "$HOST" '[ -x /usr/libexec/leandns/stats-ctl.sh ] && /usr/libexec/leandns/stats-ctl.sh pause || true
  chmod +x /etc/init.d/leandns /etc/init.d/leandns-stats /usr/bin/leandns-validate /usr/libexec/leandns/* /usr/libexec/rpcd/leandns 2>/dev/null
  /usr/libexec/leandns/www-root.sh || true
  /etc/init.d/leandns enable || true
  /etc/init.d/leandns-stats enable || true
  /etc/init.d/leandns-discover enable || true
  /etc/init.d/leandns-discover restart || true
  /etc/init.d/rpcd restart
  /etc/init.d/uhttpd restart
  /etc/init.d/leandns restart || true
  /etc/init.d/leandns-stats restart || true
  [ -x /usr/libexec/leandns/stats-ctl.sh ] && /usr/libexec/leandns/stats-ctl.sh resume || true
  echo OK: open http://'"${HOST#*@}"'/'


echo "adblock-lean Mini is bundled; enable from Web UI (Ad blocking)."
