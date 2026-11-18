# LeanDNS 아키텍처

## 목표

ASUS RT-AC750L(OpenWrt `asus_rt-ac1200-v2`)에서 AdGuard Home보다 가벼운 DNS 전용 광고 차단 관리 시스템을 제공한다. DNS 엔진은 새로 만들지 않고 dnsmasq와 adblock-lean을 사용한다.

## 구성 요소

```text
LAN Client ──DNS:53──► dnsmasq ◄── blocklist ── adblock-lean
                              │
Admin Browser ──HTTP──► uhttpd ── / and /leandns/ (same static UI)
                              └── /ubus ──► rpcd ── luci session


                                              └── leandns.uc (API)
                                                    ├── UCI (dhcp, leandns, network)
                                                    ├── adblock-lean
                                                    └── procd services
```

## 설계 결정

| 결정 | 내용 |
|------|------|
| OS | OpenWrt 24.10.x |
| DNS | dnsmasq (UDP/TCP, 캐시) |
| 차단 | adblock-lean Mini |
| 웹 | uhttpd + 정적 UI |
| API | rpcd/ubus + ucode |
| 인증 | luci-base 세션 (전체 LuCI UI 미포함) |
| DoH/DoT | 1차 제외 |
| 역할 | DNS 전용 LAN 어플라이언스 (DHCP/라우팅 비목표) |

## 네트워크 기본값

| 항목 | 기본값 |
|------|--------|
| 관리 IP | 192.168.0.250/24 |
| Gateway | 192.168.0.1 |
| DHCP 서버 | 비활성 |
| DNS | TCP/UDP 53 |
| UI | LAN만 |
| 내부 도메인 | home.arpa |

메인 공유기가 DHCP를 담당하고, LeanDNS는 DNS만 처리한다. 설치 시 메인 공유기 DNS를 자동 변경하지 않는다.

## 설정 저장

- `leandns` UCI: 관리 옵션, 캐시, IPv6 토글, 질의 로그 옵션
- `dhcp` UCI: dnsmasq upstream, 캐시 크기, 도메인
- `/etc/leandns/hosts` 또는 UCI host 섹션: 내부 정적 레코드
- `/etc/adblock-lean/config`: 차단 프리셋
- 커스텀 allow/block: adblock-lean 사용자 목록 경로

## 안전한 적용

1. 변경 전 관련 UCI/파일을 백업한다.
2. 검증(도메인·IP·숫자 범위) 통과 후에만 커밋한다.
3. 서비스 재시작 실패 시 백업을 복구하고 서비스를 재기동한다.
4. 임의 셸 명령 실행 API는 제공하지 않는다.

## 통계 정책

실측 가능한 값만 표시한다. 캐시 적중률·클라이언트별 사용량은 엔진에서 제공되지 않으면 UI에 “지원하지 않음”으로 표시한다.

차단 통계(`block_stats`)는 dnsmasq 질의 로그를 `/tmp`에서만 파싱해 **RAM 전용**으로 유지한다(재부팅 시 소멸, Flash 미기록). 최근 차단은 기본 20건, 가용 RAM이 `min_free_ram_kb`에 가까우면 10건으로 줄이고, 그보다 낮으면 수집을 일시 중지한다. adblock 목록 업데이트·DNS 재적용·패키지 설치 직전에는 pause/truncate로 tmpfs를 비운다.
