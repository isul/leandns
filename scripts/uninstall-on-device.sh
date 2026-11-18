#!/usr/bin/env bash
# Remove LeanDNS files from a device. Does not restore OEM firmware.
set -euo pipefail

HOST="${1:-}"
if [ -z "$HOST" ]; then
  echo "usage: $0 <user@host>" >&2
  exit 2
fi

ssh "$HOST" 'set -e
  /etc/init.d/leandns stop 2>/dev/null || true
  /etc/init.d/leandns disable 2>/dev/null || true
  rm -f /etc/init.d/leandns /etc/config/leandns
  rm -rf /etc/leandns /www/leandns /usr/libexec/leandns
  for f in /www/index.html /www/css /www/js; do
    [ -L "$f" ] || continue
    case "$(readlink "$f")" in
      leandns|leandns/*) rm -f "$f" ;;
    esac
  done
  if [ -f /www/cgi-bin/luci ] && grep -q 'LeanDNS: luci-base' /www/cgi-bin/luci; then
    rm -f /www/cgi-bin/luci
  fi


  rm -f /usr/libexec/rpcd/leandns /usr/share/rpcd/acl.d/leandns.json
  rm -f /usr/share/rpcd/ucode/leandns.uc /usr/bin/leandns-validate

  /etc/init.d/rpcd restart
  /etc/init.d/uhttpd restart
  echo LeanDNS removed. Network/dhcp configs were not automatically reverted.
'
