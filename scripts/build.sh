#!/usr/bin/env bash
# Build custom OpenWrt image via Image Builder for asus_rt-ac1200-v2 (RT-AC750L).
# DNS appliance profile: no Wi-Fi, no PPP. Does NOT flash any device.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPENWRT_VERSION="${OPENWRT_VERSION:-24.10.0}"
TARGET="ramips"
SUBTARGET="mt76x8"
PROFILE="asus_rt-ac1200-v2"
IB_NAME="openwrt-imagebuilder-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}.Linux-x86_64"
IB_URL="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}/${IB_NAME}.tar.zst"
WORK="$ROOT/firmware/ib"
DEST="$ROOT/firmware"

mkdir -p "$WORK" "$DEST"
"$ROOT/scripts/package.sh"

echo "==> LeanDNS Image Builder (DNS appliance / no Wi-Fi)"
echo "Version: $OPENWRT_VERSION  Profile: $PROFILE"
echo "This script will NOT write firmware to hardware."

if [ "${SKIP_DOWNLOAD:-0}" != "1" ]; then
  archive="$WORK/${IB_NAME}.tar.zst"
  if [ ! -f "$archive" ]; then
    echo "==> Downloading $IB_URL"
    if command -v curl >/dev/null; then
      curl -L --fail -o "$archive" "$IB_URL"
    else
      wget -O "$archive" "$IB_URL"
    fi
  fi
  if [ ! -d "$WORK/$IB_NAME" ]; then
    echo "==> Extracting Image Builder"
    if command -v zstd >/dev/null; then
      tar --use-compress-program=unzstd -xf "$archive" -C "$WORK"
    else
      zstd -d -c "$archive" | tar -xf - -C "$WORK"
    fi
  fi
fi

IB_DIR="$WORK/$IB_NAME"
if [ ! -d "$IB_DIR" ]; then
  echo "Image Builder directory missing: $IB_DIR" >&2
  exit 1
fi

FILES_DIR="$DEST/files"
rm -rf "$FILES_DIR"
mkdir -p "$FILES_DIR"
cp -a "$ROOT/firmware/leandns-manager-files/." "$FILES_DIR/"

# Ensure wireless stays off even if a kmod sneaks in
mkdir -p "$FILES_DIR/etc/uci-defaults"
cat > "$FILES_DIR/etc/uci-defaults/98-leandns-nowifi" <<'EOF'
#!/bin/sh
rm -f /etc/config/wireless
uci -q delete wireless 2>/dev/null || true
rm -f /etc/modules.d/*mt76* /etc/modules.d/*mac80211* /etc/modules.d/*cfg80211* 2>/dev/null || true
exit 0
EOF
chmod +x "$FILES_DIR/etc/uci-defaults/98-leandns-nowifi"

# Keep: dnsmasq, uhttpd(+ubus), rpcd, luci-base (session auth)
# Remove: Wi-Fi stack, PPP dialup (DNS appliance is LAN-only), optional IPv6 WAN helpers
PACKAGES=(
  dnsmasq
  uhttpd
  uhttpd-mod-ubus
  rpcd
  rpcd-mod-ucode
  luci-base
  # --- Wi-Fi / 802.11 (profile defaults + deps) ---
  -kmod-mt7615e
  -kmod-mt7663-firmware-ap
  -kmod-mt7603
  -kmod-mt76-core
  -kmod-mac80211
  -kmod-cfg80211
  -wpad-basic-mbedtls
  -wpad-basic
  -wpad-mini
  -hostapd-common
  -iw
  -iwinfo
  -libiwinfo20230701
  -libiwinfo-data
  -wifi-scripts
  -wireless-regdb
  -ucode-mod-nl80211
  # Wi-Fi crypto helpers often pulled by mac80211
  -kmod-crypto-ccm
  -kmod-crypto-cmac
  -kmod-crypto-gcm
  -kmod-crypto-ghash
  -kmod-crypto-ctr
  -kmod-crypto-seqiv
  -kmod-crypto-sha512
  -kmod-crypto-sha3
  # --- PPP / dial-up (not used as gateway) ---
  -ppp
  -ppp-mod-pppoe
  -kmod-ppp
  -kmod-pppoe
  -kmod-pppox
  -kmod-slhc
  -kmod-lib-crc-ccitt
  # --- IPv6 helpers unused for LAN DNS appliance ---
  -odhcpd-ipv6only
  -odhcp6c
)

DISABLED_SERVICES="wpad odhcpd"

echo "==> make image (may take several minutes)"
make -C "$IB_DIR" image \
  PROFILE="$PROFILE" \
  PACKAGES="${PACKAGES[*]}" \
  DISABLED_SERVICES="$DISABLED_SERVICES" \
  FILES="$FILES_DIR" \
  BIN_DIR="$DEST/bin"

echo "==> Outputs in $DEST/bin"
ls -lah "$DEST/bin" || true
echo "==> Package footprint (manifest Wi-Fi check)"
if [ -f "$DEST/bin"/*manifest ]; then
  if grep -E 'mt76|mac80211|cfg80211|hostapd|wpad|wifi-scripts|iwinfo' "$DEST/bin"/*manifest; then
    echo "WARNING: Wi-Fi related packages still present" >&2
  else
    echo "OK: no Wi-Fi packages in manifest"
  fi
fi
echo "DONE. Flash only after explicit user approval. See docs/installation.md"
