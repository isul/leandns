# DNS 시나리오 체크리스트

호스트에서 자동화된 항목과 실기/수동 항목을 구분한다.

## 자동 (본 저장소 테스트)

| 시나리오 | 방법 | 상태 |
|----------|------|------|
| 잘못된 도메인 입력 | `test_validate.sh`, mock `hosts_set`/`dns_set` | 자동 |
| 중복 규칙 처리 | `test_lists_dedupe.sh`, mock lists | 자동 |
| 설정 복원 | mock `backup_import` | 자동 |
| 관리자 인증 실패 | mock login wrongpassword | 자동 |
| 부적절한 API 요청 | mock unauth / invalid upstream | 자동 |
| 차단 목록 업데이트 장애 | mock `force_fail` | 자동 |

## 수동 / 실기 (미검증까지 완료 단정 금지)

| 시나리오 | 확인 방법 |
|----------|-----------|
| DNS 정상 조회 | `nslookup openwrt.org 192.168.0.250` |
| DNS 캐시 동작 | 동일 질의 반복 후 dnsmasq 로그/지연 |
| 차단 도메인 조회 | 차단 목록 도메인 → NXDOMAIN/0.0.0.0 |
| 허용 목록 예외 | allow 후 동일 도메인 해석 성공 |
| 내부 DNS 레코드 | `nas.home.arpa` → 설정 IP |
| 상위 DNS 장애 | upstream을 잘못된 IP로 변경 후 타임아웃/실패, 롤백 |
| 메모리 부족 시 업데이트 중단 | `min_free_ram_kb`를 높게 설정 후 update |
| OpenWrt 가상 환경 | QEMU/컨테이너는 스위치·플래시·RAM 특성이 실기와 다름 |

가상 환경과 RT-AC750L 차이는 `docs/hardware.md` 참고.
