# LeanDNS UDP 발견 / 네트워크 설정 툴

메인 공유기 대역이 바뀌어 관리 IP로 웹 접속이 안 될 때, **같은 스위치·공유기 LAN(L2)** 에 PC만 있으면 UDP 브로드캐스트로 장치를 찾고 IP/게이트웨이를 바꿀 수 있습니다.

## 구성

| 구성 | 설명 |
|------|------|
| 장치 데몬 | `leandns-discoverd` (C, musl) UDP **37421** |
| 토큰 | `/etc/leandns/udp.token` (웹 시스템 메뉴에 표시) |
| 토큰 스위치 | UCI `leandns.main.udp_token_required` (기본 `1`) |
| PC 툴 | Go `cmd/leandns-tool` → `dist/leandns-tool/` |

DISCOVER는 인증 없음(존재·현재 IP·토큰 필요 여부). SET은 시스템 메뉴의 「IP 변경에 토큰 필요」가 켜져 있을 때만 토큰이 필요합니다. 끄면 `--token` 없이 IP를 바꿀 수 있습니다. 값이 없으면 토큰 필요로 동작합니다.

## 빌드 (개발 PC)

```bash
./scripts/build-udp-tool.sh
```

Windows 11용: `dist/leandns-tool/leandns-tool-windows-amd64.exe`

## PC에서 (Windows 11)

```bat
leandns-tool-windows-amd64.exe discover

leandns-tool-windows-amd64.exe set ^
  --token "웹에표시된토큰" ^
  --ip 192.168.34.250 ^
  --netmask 255.255.255.0 ^
  --gateway 192.168.34.1
```

토큰 확인을 끈 장치:

```bat
leandns-tool-windows-amd64.exe set --ip 192.168.34.250 --gateway 192.168.34.1
```

Linux/macOS:

```bash
./leandns-tool-linux-amd64 discover
./leandns-tool-linux-amd64 set --token '...' --ip 192.168.34.250 --gateway 192.168.34.1
./leandns-tool-linux-amd64 set --ip 192.168.34.250 --gateway 192.168.34.1   # 토큰 확인이 꺼진 경우
```

PC는 집 메인 Wi‑Fi/유선에 연결. 방화벽이 UDP 37421 응답을 막지 않는지 확인.

## 웹 UI

시스템 → LAN IP / 게이트웨이 저장, UDP 토큰 확인·재발급, 「IP 변경에 토큰 필요」 켜기/끄기.

## 참고

- 장치 쪽 데몬은 플래시 용량 때문에 Go가 아니라 C(`cmd/leandns-discoverd/discoverd.c`)입니다.
- Python 레퍼런스 클라이언트: `host/leandns_tool.py` (동일 프로토콜).
