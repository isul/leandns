[English](../installation.md) | 한국어

# 설치 가이드

## 전제

- 대상: ASUS RT-AC750L (= OpenWrt `asus_rt-ac1200-v2`)
- 기준 OpenWrt: **24.10.x**
- 메인 공유기는 그대로 두고, 이 장치는 DNS 전용으로 연결한다.
- **펌웨어 기록은 사용자가 명시 승인한 뒤에만** 수행한다.

## Windows 11에서 factory 이미지 기록 (승인 후)

1. [ASUS Firmware Restoration](https://www.asus.com/support/) 유틸리티를 설치한다.
2. 공식 이미지 `openwrt-24.10.x-ramips-mt76x8-asus_rt-ac1200-v2-squashfs-factory.bin`를 준비한다. (또는 본 프로젝트 Image Builder 산출물)
3. PC 이더넷 IPv4를 수동 설정한다.
   - IP: `192.168.1.75`
   - 서브넷: `255.255.255.0`
   - 게이트/DNS: 비움
4. 공유기 전원 OFF → **Reset** 누른 채 전원 ON → 전원 LED가 느리게 점멸하면 Reset 해제.
5. Firmware Restoration에서 factory 이미지를 업로드한다.
6. LED 작업이 끝날 때까지 전원을 유지한 뒤 재부팅한다.

Linux에서는 `tftp` 복구가 가능할 수 있으나, 이 모델은 ASUS Windows 복구 도구가 공식 경로다.

## 최초 네트워크

기본 LeanDNS 프로파일(uci-defaults):

| 항목 | 값 |
|------|-----|
| LAN IP | 192.168.0.250/24 |
| Gateway | 192.168.0.1 |
| DHCP 서버 | 끔 |
| DNS | dnsmasq :53 |

메인 LAN에 케이블로 연결한다. 메인 공유기 DHCP 범위와 IP가 겹치지 않게 한다.

## 패키지 설치 (이미 OpenWrt가 있는 경우)

### Windows 11 (OpenSSH 클라이언트)

```bat
cd C:\path\to\LeanDNS
bash scripts\package.sh
bash scripts\install-on-device.sh root@192.168.0.250
```

Git Bash 또는 WSL에서 실행한다. `scp`/`ssh`가 PATH에 있어야 한다.

### Linux

```bash
./scripts/package.sh
./scripts/install-on-device.sh root@192.168.0.250
```

설치 전 스크립트는 원격 `/etc/config/dhcp`, `network`를 `/root/leandns-preinstall-backup`에 복사한다.

## adblock-lean

LeanDNS 이미지/패키지에 **adblock-lean Mini**가 포함된다 (`hagezi:pro.mini`, 64MB RAM용).  
전체 패키지 설치(`install-on-device.sh`)에 함께 배포된다.

웹 UI → 광고 차단 → 활성화 저장. 첫 목록 다운로드에 인터넷과 수 분이 필요할 수 있다.

업스트림 갱신(개발 호스트): `./scripts/sync-adblock-lean.sh` 후 `./scripts/package.sh`

### 부분 갱신 번들 (플래시 없음)

```bash
./scripts/make-update-bundle.sh
# Windows 11:
scp -O -r firmware\update-bundle root@192.168.0.250:/tmp/leandns-upd
ssh root@192.168.0.250 "sh /tmp/leandns-upd/install-on-device.sh /tmp/leandns-upd"
```

## 관리 UI

브라우저: `http://192.168.0.250/` (동일 UI: `http://192.168.0.250/leandns/`)

인증: OpenWrt **root** 계정 (luci-base 세션만 사용, LuCI 웹 UI 미포함). 최초 기본 암호를 반드시 변경한다.

## 메인 공유기 DNS (수동)

메인 공유기 DHCP DNS 옵션을 `192.168.0.250`으로 지정한다. LeanDNS는 이를 자동 변경하지 않는다.

## 커스텀 이미지 빌드 (플래시 없음)

Linux 빌드 호스트:

```bash
./scripts/build.sh
# 산출물: firmware/bin/
#   leandns-1.0.0-sysupgrade.bin   ← 웹 UI / sysupgrade
#   leandns-1.0.0-factory.bin      ← ASUS Firmware Restoration
#   openwrt-24.10.0-…-sysupgrade.bin / factory.bin  (원본명, 참고용)
```

Windows 11에서는 WSL2 Ubuntu에서 동일 스크립트를 실행한다.

## 제거

```bash
./scripts/uninstall-on-device.sh root@192.168.0.250
```

네트워크 UCI는 자동 원복하지 않는다. 백업 디렉터리를 참고한다.
