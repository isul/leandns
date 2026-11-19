[English](../recovery.md) | 한국어

# 복구 절차

## 중요

- 펌웨어 기록·복구 명령은 **사용자 명시 승인 전 실행하지 않는다.**
- Soft brick(부팅은 되나 UI/네트워크 이상)과 hard brick(복구 모드 필요)을 구분한다.

## Soft recovery (SSH 가능)

Windows 11 PowerShell / 명령 프롬프트:

```bat
ssh root@192.168.0.250
```

장치에서:

```sh
# LeanDNS DNS 적용 롤백
/usr/libexec/leandns/apply-dns.sh --rollback

# 설치 전 백업이 있으면
cp -a /root/leandns-preinstall-backup/dhcp /etc/config/dhcp
cp -a /root/leandns-preinstall-backup/network /etc/config/network
uci commit
reboot
```

설정만 되돌리기:

```sh
# 백업 파일을 UI에서 가져왔거나 /tmp에 있는 경우
/usr/libexec/leandns/backup.sh import /tmp/backup.b64
```

## Failsafe / 복구 모드

1. 전원 OFF
2. Reset 버튼을 누른 채 전원 ON
3. 전원 LED 느린 점멸 확인 후 Reset 해제
4. PC를 `192.168.1.75/24`로 설정 (Windows 11: 설정 → 네트워크 → 이더넷 → 편집)
5. ASUS Firmware Restoration으로 `asus_rt-ac1200-v2` **factory** 이미지 업로드
6. 완료 후 전원 유지 → 재부팅

OEM 복귀가 필요하면 ASUS 공식 RT-AC750L/RT-AC1200 V2 TRX를 동일 절차로 기록한다.

## DNS 장애 시 LAN 우회

메인 공유기 DHCP DNS를 공용 DNS(예: 1.1.1.1)로 되돌리면 클라이언트는 LeanDNS를 거치지 않는다. LeanDNS 장치 자체 복구와 별개로 즉시 인터넷 DNS를 회복할 수 있다.

## 로그

```sh
logread | grep -E 'leandns|dnsmasq|adblock'
```
