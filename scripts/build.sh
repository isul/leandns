#!/usr/bin/env bash
# Build custom OpenWrt image via Image Builder for asus_rt-ac1200-v2 (RT-AC750L).
# DNS appliance profile: no Wi-Fi, no PPP, slim LuCI/firewall. Does NOT flash any device.
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
"$ROOT/scripts/build-discoverd.sh"
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

# Fail the build if the password-check fix is missing from FILES overlay.
# (Stale firmware/files or a skipped package.sh used to ship the old UCI-only check.)
RPCD_PLUGIN="$FILES_DIR/usr/libexec/rpcd/leandns"
if [ ! -f "$RPCD_PLUGIN" ]; then
  echo "ERROR: missing $RPCD_PLUGIN in FILES overlay" >&2
  exit 1
fi
if ! grep -q "/etc/shadow" "$RPCD_PLUGIN" || ! grep -q "root:\[^!\\*:x\]" "$RPCD_PLUGIN"; then
  echo "ERROR: $RPCD_PLUGIN lacks /etc/shadow password detection; refusing to build" >&2
  exit 1
fi
echo "OK: FILES overlay auth_required checks /etc/shadow"

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

# A: After package_install, strip unused LuCI UI bits before squashfs packing.
# Login uses rpcd ubus session only — luci-static is not referenced.
if ! grep -q 'leandns_strip_luci' "$IB_DIR/Makefile"; then
  IB_MAKEFILE="$IB_DIR/Makefile" python3 - <<'PY'
from pathlib import Path
import os
path = Path(os.environ["IB_MAKEFILE"])
text = path.read_text()
needle = "\t$(MAKE) package_install\n\t$(MAKE) -s prepare_rootfs\n"
inject = """\t$(MAKE) package_install
\t# leandns_strip_luci: drop unused LuCI UI / helpers from DNS appliance rootfs
\t@rm -rf $(TARGET_DIR)/www/luci-static \\
\t\t$(TARGET_DIR)/usr/share/ucode/luci \\
\t\t$(TARGET_DIR)/usr/lib/ucode/luci \\
\t\t$(TARGET_DIR)/usr/share/luci \\
\t\t$(TARGET_DIR)/usr/share/rpcd/ucode/luci \\
\t\t$(TARGET_DIR)/usr/lib/rpcd/luci.so \\
\t\t$(TARGET_DIR)/etc/config/luci \\
\t\t$(TARGET_DIR)/etc/luci-uploads
\t$(MAKE) -s prepare_rootfs
"""
if needle not in text:
    raise SystemExit(f"Makefile hook point not found in {path}")
path.write_text(text.replace(needle, inject, 1))
print(f"Patched {path}")
PY
fi

# Keep: dnsmasq, uhttpd(+ubus), rpcd (session auth via ubus; no LuCI UI)
# Remove: Wi-Fi, PPP, odhcp helpers, luci-base UI stack, firewall4/nft NAT+offload stack
PACKAGES=(
  dnsmasq
  uhttpd
  uhttpd-mod-ubus
  rpcd
  rpcd-mod-ucode
  # Keep ucode modules that luci-base used to pull transitively (rpcd/ucode helpers).
  ucode-mod-uci
  ucode-mod-ubus
  # --- A: LuCI UI unused (login uses rpcd session only) ---
  -luci-base
  -rpcd-mod-luci
  -liblucihttp0
  -liblucihttp-ucode
  -ucode-mod-html
  -cgi-io
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
  # --- C: firewall4/nft offload/NAT; LAN DNS appliance sits behind main router ---
  # Default profile uses package name "nftables" (resolves to nftables-json).
  -firewall4
  -nftables
  -nftables-json
  -libnftnl11
  -kmod-nft-offload
  -kmod-nft-nat
  -kmod-nft-fib
  -kmod-nft-core
  -kmod-nf-flow
  -kmod-nf-nat
  -kmod-nf-conntrack
  -kmod-nf-conntrack6
  -kmod-nf-reject
  -kmod-nf-reject6
  -kmod-nf-log
  -kmod-nf-log6
  -kmod-nfnetlink
  -kmod-lib-crc32c
  -kmod-crypto-crc32c
  -jansson4
)

# adblock-lean: do not run enable on the build host (/bin/sh is often dash and
# fails its process-substitution check). Service is enabled via FILES rc.d links.
DISABLED_SERVICES="wpad odhcpd firewall adblock-lean"

echo "==> make image (may take several minutes)"
make -C "$IB_DIR" image \
  PROFILE="$PROFILE" \
  PACKAGES="${PACKAGES[*]}" \
  DISABLED_SERVICES="$DISABLED_SERVICES" \
  FILES="$FILES_DIR" \
  BIN_DIR="$DEST/bin"

echo "==> Outputs in $DEST/bin"
ls -lah "$DEST/bin" || true

# Confirm the packed rootfs actually received the FILES overlay (not a stale copy).
ROOTFS_PLUGIN="$IB_DIR/build_dir/target-mipsel_24kc_musl/root-ramips/usr/libexec/rpcd/leandns"
if [ -f "$ROOTFS_PLUGIN" ]; then
  if grep -q "/etc/shadow" "$ROOTFS_PLUGIN"; then
    echo "OK: rootfs auth_required checks /etc/shadow"
  else
    echo "ERROR: rootfs $ROOTFS_PLUGIN still has old UCI-only password check" >&2
    exit 1
  fi
else
  echo "WARNING: could not find packed rootfs plugin at $ROOTFS_PLUGIN" >&2
fi

# Friendly distribution names (keep OpenWrt IB originals for support/debug).
LEAN_VER="$(tr -d ' \t\r\n' < "$ROOT/package/leandns-manager/files/etc/leandns/version" 2>/dev/null || true)"
LEAN_VER="${LEAN_VER:-1.0.0}"
IB_PREFIX="openwrt-${OPENWRT_VERSION}-${TARGET}-${SUBTARGET}-${PROFILE}-squashfs"
SYSU_SRC="$DEST/bin/${IB_PREFIX}-sysupgrade.bin"
FACT_SRC="$DEST/bin/${IB_PREFIX}-factory.bin"
if [ -f "$SYSU_SRC" ]; then
  cp -f "$SYSU_SRC" "$DEST/bin/leandns-${LEAN_VER}-sysupgrade.bin"
  cp -f "$SYSU_SRC" "$DEST/bin/leandns-sysupgrade.bin"
  echo "==> Dist: leandns-${LEAN_VER}-sysupgrade.bin (and leandns-sysupgrade.bin)"
else
  echo "ERROR: expected sysupgrade image missing: $SYSU_SRC" >&2
  exit 1
fi
if [ -f "$FACT_SRC" ]; then
  cp -f "$FACT_SRC" "$DEST/bin/leandns-${LEAN_VER}-factory.bin"
  cp -f "$FACT_SRC" "$DEST/bin/leandns-factory.bin"
  echo "==> Dist: leandns-${LEAN_VER}-factory.bin (and leandns-factory.bin)"
fi

echo "==> Package footprint checks"
if [ -f "$DEST/bin"/*manifest ]; then
  if grep -E 'mt76|mac80211|cfg80211|hostapd|wpad|wifi-scripts|iwinfo' "$DEST/bin"/*manifest; then
    echo "WARNING: Wi-Fi related packages still present" >&2
  else
    echo "OK: no Wi-Fi packages in manifest"
  fi
  if grep -E '^(luci-base|firewall4|nftables|kmod-nft-|kmod-nf-)' "$DEST/bin"/*manifest; then
    echo "WARNING: LuCI/firewall/nft packages still present" >&2
  else
    echo "OK: no luci-base / firewall4 / nft stack in manifest"
  fi
fi
echo "DONE. Flash only after explicit user approval. See docs/installation.md"
echo "Web upgrade file: firmware/bin/leandns-${LEAN_VER}-sysupgrade.bin"
