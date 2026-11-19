English | [한국어](ko/hardware.md)

# Hardware Compatibility: ASUS RT-AC750L

## Verified Facts

| Item | Detail | Source |
|------|--------|--------|
| Model mapping | RT-AC750L = RT-AC1200 V2 | OpenWrt `DEVICE_ALT0`, [PR #12019](https://github.com/openwrt/openwrt/pull/12019), [forum](https://forum.openwrt.org/t/asus-rt-ac750l-is-the-same-as-rt-ac1200-v2/151783) |
| OEM firmware | RT-AC750L / RT-AC1200_V2 TRX SHA256 identical | Forum-reported value `79cae1a3…c42bdc` |
| SoC | MediaTek MT7628DAN, MIPS 24KEc ~580 MHz | OpenWrt device PR #9415 |
| Wi-Fi | 2.4 GHz SoC built-in, 5 GHz MT7613BEN | Same |
| Flash | 16 MiB SPI-NOR (IMAGE_SIZE 16064k) | OpenWrt `mt76x8.mk` |
| RAM | 64 MiB (SoC built-in) | ASUS spec / OpenWrt |
| Ethernet | 100 Mbps × 5 (WAN+LAN) | ASUS spec |
| USB | None | ASUS spec |
| OpenWrt target | `ramips/mt76x8`, profile `asus_rt-ac1200-v2` | downloads.openwrt.org |
| Supported versions | 23.05.x, 24.10.x images available | Official downloads |
| LeanDNS base version | **OpenWrt 24.10.x** | This project |

Official image filenames (example):

```text
openwrt-24.10.x-ramips-mt76x8-asus_rt-ac1200-v2-squashfs-factory.bin
openwrt-24.10.x-ramips-mt76x8-asus_rt-ac1200-v2-squashfs-sysupgrade.bin
```

Do not use RT-AC1200 (non-V2) images.

## Image Size (reference measurements, host download)

| Version | factory | sysupgrade |
|---------|---------|------------|
| 23.05.5 | ~6272 KB | ~6272 KB |
| 24.10.0 | ~5952 KB | ~5952 KB |

The base image has ample headroom within 16 MiB flash, but full LuCI, large blocklists, and additional packages will quickly consume the overlay.

## 64 MiB RAM Risk

- Recent OpenWrt leaves very little headroom on 64 MiB.
- LeanDNS default: **DNS-only**, removes Wi-Fi, PPP, odhcp, luci-base UI, firewall4/nft NAT, and offload; uses adblock-lean **Mini** (~85k, `hagezi:pro.mini`).
- Peak RSS during blocklist update can only be measured **on real hardware**. Do not assume "enough headroom" before measuring.

## Installation Overview (after approval)

1. ASUS Firmware Restoration utility (Windows).
2. Power off → hold Reset, power on → release Reset when power LED blinks slowly.
3. Set PC to `192.168.1.75/24`.
4. Upload `asus_rt-ac1200-v2` **factory** image.
5. Keep power until LED activity completes, then reboot.

Details: [installation.md](installation.md), [recovery.md](recovery.md).

## Deployment Gates

| Task | Status |
|------|--------|
| Repository code, packages, UI, tests | In progress |
| Image Builder image generation | In progress (no auto-flash) |
| Writing firmware to real device | **Blocked until explicit user approval** |
| Destructive network configuration apply | **Blocked until approval** |

If a compatible image is unavailable or revision mismatches, **block real-device deployment** and continue with development/host testing only.

## Needs Verification (no guessing)

- [ ] PCB ID / hardware revision measured on actual device
- [ ] Free RAM after real boot
- [ ] adblock-lean Mini update peak memory
- [ ] Overlay headroom with luci-base + leandns-manager included
- [ ] Factory recovery mode entry confirmed on this board

## Virtual vs Real Hardware

| Item | Host/simulated | RT-AC750L real hardware |
|------|---------------|------------------------|
| UI/API schema | Validated with mock | Same schema |
| dnsmasq behavior | Container/local possible | SoC/cache limits differ |
| Memory/Flash | Cannot measure or estimate | Must measure on device |
| Switch/bridge | Simplified | mt7628 switch actual behavior |
| Wi-Fi-removed image | Build verified | Real boot confirmation needed |
