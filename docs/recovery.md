English | [한국어](ko/recovery.md)

# Recovery Procedures

## Important

- Firmware flashing and recovery commands **must not be executed without explicit user approval.**
- Distinguish between soft brick (device boots but UI/network is broken) and hard brick (recovery mode required).

## Soft Recovery (SSH accessible)

Windows 11 PowerShell / Command Prompt:

```bat
ssh root@192.168.0.250
```

On the device:

```sh
# Roll back LeanDNS DNS apply
/usr/libexec/leandns/apply-dns.sh --rollback

# If pre-install backup exists
cp -a /root/leandns-preinstall-backup/dhcp /etc/config/dhcp
cp -a /root/leandns-preinstall-backup/network /etc/config/network
uci commit
reboot
```

Restore settings only:

```sh
# If backup file was imported from UI or is available in /tmp
/usr/libexec/leandns/backup.sh import /tmp/backup.b64
```

## Failsafe / Recovery Mode

1. Power off
2. Hold Reset button, then power on
3. Confirm power LED blinking slowly, then release Reset
4. Set PC to `192.168.1.75/24` (Windows 11: Settings → Network → Ethernet → Edit)
5. Upload `asus_rt-ac1200-v2` **factory** image using ASUS Firmware Restoration
6. Keep power on until complete, then reboot

To return to OEM firmware, follow the same procedure with the official ASUS RT-AC750L/RT-AC1200 V2 TRX.

## LAN Bypass on DNS Failure

Revert the main router's DHCP DNS to a public DNS (e.g., 1.1.1.1) so clients bypass LeanDNS. This restores internet DNS access independently of LeanDNS device recovery.

## Logs

```sh
logread | grep -E 'leandns|dnsmasq|adblock'
```
