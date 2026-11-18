# LeanDNS

ASUS **RT-AC750L**(OpenWrt `asus_rt-ac1200-v2`)용 초경량 스마트 DNS 관리 시스템.

AdGuard Home과 비슷한 관리 경험을 목표로 하되, **dnsmasq + adblock-lean + uhttpd/rpcd** 위에 정적 웹 UI만 올린다. DNS 엔진은 새로 만들지 않는다.

> **실기 플래시·파괴적 네트워크 적용은 사용자 승인 전까지 수행하지 않는다.**  
> RT-AC750L에서의 안정 동작은 실측 전까지 **미검증**이다.

## 구성

| 구성 | 선택 |
|------|------|
| 대상 | RT-AC750L = RT-AC1200 V2, 64MB RAM / 16MB Flash |
| OS | OpenWrt 24.10.x (`ramips/mt76x8`) |
| DNS | dnsmasq |
| 광고 차단 | adblock-lean Mini |
| UI | `/www/leandns` 정적 HTML/CSS/JS (한국어) |
| API | `/usr/libexec/rpcd/leandns` + ACL |
| 인증 | luci-base 세션 (전체 LuCI UI 미포함) |

## 빠른 시작 (호스트 미리보기)

```bash
./host/run.sh
# 브라우저: http://127.0.0.1:8765/
# 로그인: 임의 사용자 / 임의 비밀번호 (wrongpassword 제외)
```

Windows 11: WSL2 또는 Python3가 있는 환경에서 동일하게 실행.

## 테스트

```bash
./scripts/test.sh
```

## 패키지·이미지

```bash
./scripts/package.sh          # 웹 동기화 + 파일 트리 스테이징
./scripts/measure-size.sh     # 크기 측정 → docs/metrics.md
./scripts/build.sh            # Image Builder (다운로드·빌드만, 플래시 없음)
./scripts/install-on-device.sh root@192.168.0.250   # SSH 파일 설치 (플래시 없음)
```

## 문서

- [docs/hardware.md](docs/hardware.md) — 호환성·배포 게이트
- [docs/architecture.md](docs/architecture.md) — 아키텍처
- [docs/installation.md](docs/installation.md) — 설치
- [docs/recovery.md](docs/recovery.md) — 복구
- [docs/security.md](docs/security.md) — 보안
- [docs/metrics.md](docs/metrics.md) — 크기 측정

## 디렉터리

```text
LeanDNS/
├── package/leandns-manager/   # OpenWrt 패키지
├── web/                       # UI 소스
├── host/                      # 로컬 mock 서버
├── scripts/                   # build/test/package/install
├── tests/
├── configs/
├── docs/
└── firmware/                  # 빌드 산출물 (gitignore)
```

## 기본 네트워크

- IP `192.168.0.250/24`, GW `192.168.0.1`, DHCP 서버 끔
- 메인 공유기가 DHCP·업링크를 담당하고, 이 장치는 DNS만 처리

## 완료 범위

저장소에는 관리 코드, UI, 연동 스크립트, 빌드/테스트, 문서가 포함된다.  
**RT-AC750L 실기 검증·플래시는 승인 및 실측 후** 완료로 본다.
