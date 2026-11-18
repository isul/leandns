# LeanDNS 크기·리소스 측정

측정일(호스트): 2026-11-18T00:14:00+09:00  
OpenWrt Image Builder: 24.10.0 / `asus_rt-ac1200-v2`  
프로파일: **DNS appliance (Wi-Fi/PPP 제거)**

## 호스트 실측

| 항목 | 이전 (Wi-Fi 포함) | 현재 (슬림) |
|------|-------------------|-------------|
| factory.bin | 4.9 MB | **4.2 MB** |
| sysupgrade.bin | 4.9 MB | **4.2 MB** |
| squashfs rootfs (압축) | ~2954 KB | **~2237 KB** |
| Wi-Fi 패키지 | mt76/mac80211 등 포함 | **없음 (manifest 확인)** |

경로: `firmware/bin/`

포함: LeanDNS UI, `uhttpd-mod-ubus`, `leandns-discoverd`, 네트워크 설정 API.

## 제거된 주요 구성

- Wi-Fi: mt76*, mac80211, cfg80211, hostapd/wpad, iw/iwinfo, wifi-scripts, wireless-regdb
- PPP: ppp, pppoe 및 관련 kmod
- IPv6 헬퍼: odhcpd-ipv6only, odhcp6c

## 실기 미측정

부팅 후 free RAM / overlay / adblock peak RSS — 실기 필요.
