[English](../security.md) | 한국어

# 보안

## 인증

- 관리 UI는 인증 없이 사용할 수 없다.
- 장치에서는 luci-base/`session` ubus 로그인을 재사용한다.
- 호스트 mock은 개발용이며 장치에 설치되지 않는다.
- 로그인 화면의 "root 비밀번호 없음" 경고는 `/etc/shadow`의 root 해시 유무로 판단한다. (`leandns.main.force_password_change`는 캐시이며, SSH `passwd`만으로는 UCI가 안 바뀌어도 shadow 검사로 경고가 사라진다.)

## 네트워크 노출

- UI: LAN 접근을 전제로 한다 (`uhttpd` rfc1918_filter).
- DNS: `localservice`로 로컬 서브넷 질의만 허용하는 구성을 기본으로 한다.
- 인터넷에 DNS 재귀를 공개하지 않는다.

## API 보호

- rpcd ACL (`leandns.json`)으로 메서드 단위 read/write 분리.
- 임의 Shell 실행 API 없음. 허용된 helper만 호출.
- 도메인/IP/캐시 크기 등 입력 검증 (`leandns-validate`).
- 웹 UI는 textContent 위주로 XSS 표면을 줄인다.
- 외부 차단 목록은 도메인 라인만 허용하도록 sync 단계에서 걸러낸다.

## CSRF

- ubus 세션 토큰이 요청에 필요하다. 세션 없는 브라우저 사이트에서는 호출할 수 없다.
- mock 모드는 `X-Session` 헤더를 사용한다.

## 백업 파일

- 내보내기 파일에 DNS/호스트/목록 설정이 포함된다. 안전하게 보관한다.
- 펌웨어 업그레이드는 로그인 세션이 있는 관리자만 가능하며, 이미지는 `/tmp`에 한 번만 저장한다.
- 자동 다운로드/자동 플래시는 하지 않는다. 적용은 UI에서 명시 확인 후에만 진행한다.

## 질의 로그

- 기본 비활성. 활성화 시 개인정보(방문 도메인)가 남을 수 있음을 UI 도움말에 고지한다.
