[English](../udp-tool.md) | 한국어

# LeanDNS UDP 발견 / 네트워크 설정 툴

메인 공유기 대역이 바뀌어 관리 IP로 웹 접속이 안 될 때, **같은 스위치·공유기 LAN(L2)** 에 PC에서 UDP 브로드캐스트로 장치를 찾을 수 있습니다. IP 변경은 관리자가 미리 허용한 장치에서 토큰으로 요청합니다.

## 구성

| 구성 | 설명 |
|------|------|
| 장치 데몬 | `leandns-discoverd` (C mipsel softfloat) UDP **37421** |
| 토큰 | `/etc/leandns/udp.token` (웹 시스템 메뉴에서 표시 또는 재발급) |
| UDP IP 변경 | UCI `leandns.main.udp_set_enabled` (기본 `1`, 항상 허용) |
| UDP 토큰 | UCI `leandns.main.udp_token_required` (기본 `1`) |
| PC 툴 | Go `cmd/leandns-tool` → `dist/leandns-tool/` |
| Android 앱 | Kotlin `android/leandns-tool/` (동일 프로토콜) |

DISCOVER는 인증 없이 현재 설정과 토큰 필요 여부(`token_required`)·SET 허용(`set_enabled`)을 반환합니다. 시스템 화면 「UDP IP 변경에 토큰 필요」가 켜져 있으면 SET에 토큰이 필요하고, 꺼져 있으면 토큰 없이 SET 할 수 있습니다. 웹 UI의 「네트워크 적용」은 즉시 영구 반영됩니다. UDP SET만 임시 적용되며, 새 주소에서 로그인한 뒤 시스템 화면에서 120초 안에 확정하세요. 기한이 지나면 기존 LAN 설정을 복구합니다.

## 빌드 (개발 PC)

```bash
./scripts/build-udp-tool.sh
./scripts/build-discoverd.sh      # 장치용 C mipsel softfloat 데몬
./scripts/make-update-bundle.sh   # 웹+API+데몬 부분 갱신 번들
```

Windows 11용 PC 툴: `dist/leandns-tool/leandns-tool-windows-amd64.exe` (`dist/`는 gitignore)

### 장치 데몬·UI 부분 갱신 (Windows 11, 플래시 없음)

```bat
bash scripts\make-update-bundle.sh
scp -O -r firmware\update-bundle root@192.168.200.250:/tmp/leandns-upd
ssh root@192.168.200.250 "sh /tmp/leandns-upd/install-on-device.sh /tmp/leandns-upd"
```

IP는 장치 관리 주소에 맞게 바꿉니다.

## PC에서 (Windows 11)

```bat
leandns-tool-windows-amd64.exe discover

leandns-tool-windows-amd64.exe set ^
  --token "웹에표시된토큰" ^
  --ip 192.168.34.250 ^
  --netmask 255.255.255.0 ^
  --gateway 192.168.34.1
```

Linux/macOS:

```bash
./leandns-tool-linux-amd64 discover
./leandns-tool-linux-amd64 set --token '...' --ip 192.168.34.250 --gateway 192.168.34.1
```

PC는 집 메인 Wi‑Fi/유선에 연결. 방화벽이 UDP 37421 응답을 막지 않는지 확인.

## Android

프로젝트: [`android/leandns-tool/`](../../android/leandns-tool/). PC 툴과 같은 DISCOVER / SET를 제공합니다.

### Windows 11에서 APK 빌드

1. Android Studio 설치 후 SDK 35 준비
2. `android\leandns-tool` 폴더를 연다
3. **Build → Build APK(s)** 또는:

```bat
cd C:\path\to\LeanDNS\android\leandns-tool
gradlew.bat assembleDebug
```

산출물: `app\build\outputs\apk\debug\app-debug.apk`

폰을 집 메인 Wi‑Fi에 연결한 뒤 앱에서 **검색** → 장치 선택 → 필요 시 토큰 입력 → **적용**.

## 웹 UI

시스템 화면에서 LAN 설정 즉시 적용, UDP 임시 변경 확정, UDP 토큰 필요 여부, 토큰 표시와 재발급을 관리합니다.

## 참고

- 장치 쪽 데몬: C `cmd/leandns-discoverd/discoverd.c` → `./scripts/build-discoverd.sh` (mipsel softfloat musl).
- Android 클라이언트: `android/leandns-tool/` (동일 프로토콜).
