English | [한국어](ko/installation.md)

# Installation Guide

## Prerequisites

- Target device: ASUS RT-AC750L (= OpenWrt `asus_rt-ac1200-v2`)
- Base OpenWrt: **24.10.x**
- Leave the main router as-is; this device connects as DNS-only.
- **Firmware flashing must only be performed after explicit user approval.**

## Flashing the Factory Image on Windows 11 (after approval)

1. Install the [ASUS Firmware Restoration](https://www.asus.com/support/) utility.
2. Prepare the official image `openwrt-24.10.x-ramips-mt76x8-asus_rt-ac1200-v2-squashfs-factory.bin` (or the Image Builder output from this project).
3. Set the PC Ethernet IPv4 manually:
   - IP: `192.168.1.75`
   - Subnet: `255.255.255.0`
   - Gateway/DNS: leave empty
4. Power off router → hold **Reset**, power on → release Reset when the power LED blinks slowly.
5. Upload the factory image in Firmware Restoration.
6. Keep power on until the LED activity completes, then reboot.

`tftp` recovery may be possible on Linux, but the ASUS Windows recovery tool is the official path for this model.

## Initial Network

Default LeanDNS profile (uci-defaults):

| Item | Value |
|------|-------|
| LAN IP | 192.168.0.250/24 |
| Gateway | 192.168.0.1 |
| DHCP server | Off |
| DNS | dnsmasq :53 |

Connect via cable to the main LAN. Ensure the IP does not conflict with the main router's DHCP range.

## Package Installation (if OpenWrt is already running)

### Windows 11 (OpenSSH client)

```bat
cd C:\path\to\LeanDNS
bash scripts\package.sh
bash scripts\install-on-device.sh root@192.168.0.250
```

Run in Git Bash or WSL. `scp`/`ssh` must be in PATH.

### Linux

```bash
./scripts/package.sh
./scripts/install-on-device.sh root@192.168.0.250
```

Before installation, the script copies the remote `/etc/config/dhcp` and `network` to `/root/leandns-preinstall-backup`.

## adblock-lean

**adblock-lean Mini** is included in the LeanDNS image/package (`hagezi:pro.mini`, sized for 64 MB RAM).  
Deployed together with the full package installation (`install-on-device.sh`).

Web UI → Ad Blocking → Enable and save. The first list download requires internet access and may take a few minutes.

Upstream sync (dev host): run `./scripts/sync-adblock-lean.sh` then `./scripts/package.sh`

### Partial Update Bundle (no flash)

```bash
./scripts/make-update-bundle.sh
# Windows 11:
scp -O -r firmware\update-bundle root@192.168.0.250:/tmp/leandns-upd
ssh root@192.168.0.250 "sh /tmp/leandns-upd/install-on-device.sh /tmp/leandns-upd"
```

## Management UI

Browser: `http://192.168.0.250/` (same UI at `http://192.168.0.250/leandns/`)

Authentication: OpenWrt **root** account (uses luci-base session only; LuCI web UI not included). Change the default root password immediately.

## Main Router DNS (manual)

Set the main router's DHCP DNS option to `192.168.0.250`. LeanDNS does not change this automatically.

## Custom Image Build (no flash)

Linux build host:

```bash
./scripts/build.sh
# Output: firmware/bin/
#   leandns-1.0.0-sysupgrade.bin   ← web UI / sysupgrade
#   leandns-1.0.0-factory.bin      ← ASUS Firmware Restoration
#   openwrt-24.10.0-…-sysupgrade.bin / factory.bin  (original names, for reference)
```

On Windows 11, run the same script inside WSL2 Ubuntu.

## Uninstall

```bash
./scripts/uninstall-on-device.sh root@192.168.0.250
```

Network UCI is not automatically reverted. Refer to the backup directory.
