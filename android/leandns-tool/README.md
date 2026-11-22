# LeanDNS Tool (Android)

PC용 `cmd/leandns-tool`과 동일한 **LEANDNS1 / UDP 37421** 프로토콜로 LeanDNS 장치를 찾고 LAN IP를 변경하는 Android 앱입니다.

## 기능

| 기능 | 설명 |
|------|------|
| 장치 검색 | `DISCOVER` 브로드캐스트 → 이름·IP·마스크·GW·MAC·버전·토큰 필요 여부 |
| LAN 설정 | `SET`으로 IP/마스크/게이트웨이 즉시 영구 적용 (장치에서 UDP IP 변경 허용 시) |
| 웹 UI | 발견·적용 후 `http://<ip>/leandns/` 브라우저 실행 |

## 요구 사항

- Android 8.0+ (API 26)
- 장치와 **같은 Wi‑Fi / 공유기 LAN**
- 빌드: Android Studio Ladybug+ / JDK 17 / Android SDK 35

## Windows 11에서 빌드

1. [Android Studio](https://developer.android.com/studio) 설치 후 SDK 35·Build-Tools 설치
2. Android Studio에서 `android\leandns-tool` 폴더 열기
3. 메뉴 **Build → Build Bundle(s) / APK(s) → Build APK(s)**

또는 PowerShell / cmd:

```bat
cd C:\path\to\LeanDNS\android\leandns-tool
gradlew.bat assembleDebug
```

산출물: `app\build\outputs\apk\debug\app-debug.apk`

릴리스:

```bat
gradlew.bat assembleRelease
```

## 사용

1. 폰을 집 메인 Wi‑Fi에 연결
2. 앱에서 **검색**
3. 장치를 탭해 폼을 채운 뒤 필요 시 토큰 입력 → **적용** (기기에 즉시 영구 반영)
4. 새 주소의 웹 UI로 접속해 확인

토큰은 LeanDNS 웹 → 시스템 화면에서 확인합니다. 「IP 변경에 토큰 필요」가 꺼져 있으면 토큰을 비웁니다.

## 소스 대응

| Android | PC 툴 |
|---------|-------|
| `udp/LeanDnsProtocol.kt` | `cmd/leandns-tool/main.go` 프로토콜 상수·JSON |
| `udp/LeanDnsUdpClient.kt` | `sendRecv` 브로드캐스트/수신 |
| `ToolViewModel` + UI | `discover` / `set` 명령 |

## 라이선스

LeanDNS와 동일하게 **GPL-2.0-only**. 저장소 루트 [LICENSE](../../LICENSE)를 보세요.
