# 하드웨어 호환성: ASUS RT-AC750L

## 검증된 사실

| 항목 | 내용 | 근거 |
|------|------|------|
| 모델 매핑 | RT-AC750L = RT-AC1200 V2 | OpenWrt `DEVICE_ALT0`, [PR #12019](https://github.com/openwrt/openwrt/pull/12019), [포럼](https://forum.openwrt.org/t/asus-rt-ac750l-is-the-same-as-rt-ac1200-v2/151783) |
| OEM 펌웨어 | RT-AC750L / RT-AC1200_V2 TRX SHA256 동일 | 포럼 보고값 `79cae1a3…c42bdc` |
| SoC | MediaTek MT7628DAN, MIPS 24KEc ~580 MHz | OpenWrt device PR #9415 |
| Wi-Fi | 2.4 GHz SoC 내장, 5 GHz MT7613BEN | 동일 |
| Flash | 16 MiB SPI-NOR (IMAGE_SIZE 16064k) | OpenWrt `mt76x8.mk` |
| RAM | 64 MiB (SoC 내장) | ASUS 스펙 / OpenWrt |
| 이더넷 | 100 Mbps × 5 (WAN+LAN) | ASUS 스펙 |
| USB | 없음 | ASUS 스펙 |
| OpenWrt 타깃 | `ramips/mt76x8`, profile `asus_rt-ac1200-v2` | downloads.openwrt.org |
| 지원 버전 | 23.05.x, 24.10.x 이미지 존재 | 공식 다운로드 |
| LeanDNS 기준 버전 | **OpenWrt 24.10.x** | 본 프로젝트 고정 |

공식 이미지 파일명 예:

```text
openwrt-24.10.x-ramips-mt76x8-asus_rt-ac1200-v2-squashfs-factory.bin
openwrt-24.10.x-ramips-mt76x8-asus_rt-ac1200-v2-squashfs-sysupgrade.bin
```

RT-AC1200 (비-V2) 이미지는 사용하지 않는다.

## 이미지 크기 (참고 실측, 호스트 다운로드 기준)

| 버전 | factory | sysupgrade |
|------|---------|------------|
| 23.05.5 | ~6272 KB | ~6272 KB |
| 24.10.0 | ~5952 KB | ~5952 KB |

16 MiB flash 대비 기본 이미지는 여유가 있으나, LuCI 전체·대형 차단목록·추가 패키지는 overlay를 빠르게 소모한다.

## 64 MiB RAM 리스크

- 최신 OpenWrt는 64 MiB에서 여유가 매우 적다.
- LeanDNS 기본: **DNS 전용**, Wi-Fi·PPP·odhcp·luci-base UI·firewall4/nft NAT·offload 제거, adblock-lean **Mini** (~85k, `hagezi:pro.mini`).
- 차단목록 업데이트 중 peak RSS는 **실기에서만** 측정 가능. 측정 전 “여유 충분”으로 단정하지 않는다.

## 설치 개요 (승인 후)

1. ASUS Firmware Restoration 유틸리티 (Windows).
2. 전원 끄기 → Reset 누른 채 전원 켜기 → 전원 LED 느리게 점멸 시 해제.
3. PC를 `192.168.1.75/24`로 고정.
4. `asus_rt-ac1200-v2` **factory** 이미지 업로드.
5. LED 점멸이 끝날 때까지 전원 유지 후 재부팅.

상세: [installation.md](installation.md), [recovery.md](recovery.md).

## 배포 게이트

| 작업 | 상태 |
|------|------|
| 저장소 코드·패키지·UI·테스트 | 진행 |
| Image Builder로 이미지 생성 | 진행 (자동 플래시 없음) |
| 실제 장치 펌웨어 기록 | **사용자 명시 승인 전 금지** |
| 네트워크 파괴적 설정 적용 | **승인 전 금지** |

호환 이미지가 없거나 리비전이 불일치하면 **실기 배포를 차단**하고 개발·호스트 테스트만 계속한다.

## 확인 필요 (추측 금지)

- [ ] 보유 장치의 PCB ID / 하드웨어 리비전 실측
- [ ] 실기 부팅 후 free RAM
- [ ] adblock-lean Mini 업데이트 peak 메모리
- [ ] luci-base + leandns-manager 포함 후 overlay 여유
- [ ] 해당 보드에서 factory 복구 모드 진입 성공 여부

## 가상 환경 vs 실기

| 항목 | 호스트/모의 | RT-AC750L 실기 |
|------|-------------|----------------|
| UI·API 스키마 | mock으로 검증 | 동일 스키마 |
| dnsmasq 동작 | 컨테이너/로컬 가능 | SoC·캐시 한계 상이 |
| 메모리/Flash | 측정 불가 또는 추정 | 필수 실측 |
| 스위치/브리지 | 단순화 | mt7628 스위치 실제 동작 |
| Wi-Fi 제거 이미지 | 빌드 검증 | 실기 부팅 확인 필요 |
