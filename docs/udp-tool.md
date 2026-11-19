English | [한국어](ko/udp-tool.md)

# LeanDNS UDP Discovery / Network Configuration Tool

When the main router subnet changes and you can no longer reach the management IP, you can discover the device via UDP broadcast from a PC on the **same switch/router LAN (L2)**. IP changes are requested with a token on devices where the admin has pre-enabled it.

## Configuration

| Item | Description |
|------|-------------|
| Device daemon | `leandns-discoverd` (C mipsel softfloat) UDP **37421** |
| Token | `/etc/leandns/udp.token` (view or regenerate in the web System menu) |
| UDP IP change | UCI `leandns.main.udp_set_enabled` (default `1`, always allowed) |
| UDP token | UCI `leandns.main.udp_token_required` (default `1`) |
| PC tool | Go `cmd/leandns-tool` → `dist/leandns-tool/` |
| Android app | Kotlin `android/leandns-tool/` (same protocol) |

DISCOVER returns current settings and `token_required`/`set_enabled` flags without authentication. If "Require token for UDP IP change" is on in the System screen, a token is required for SET; if off, SET can be performed without a token. The web UI "Apply Network" is permanent and immediate. Only UDP SET is temporary — log in from the new address and confirm in the System screen within 120 seconds, or the previous LAN settings will be restored.

## Build (dev PC)

```bash
./scripts/build-udp-tool.sh
./scripts/build-discoverd.sh      # device-side C mipsel softfloat daemon
./scripts/make-update-bundle.sh   # web+API+daemon partial update bundle
```

PC tool for Windows 11: `dist/leandns-tool/leandns-tool-windows-amd64.exe` (`dist/` is gitignored)

### Partial Device Daemon/UI Update (Windows 11, no flash)

```bat
bash scripts\make-update-bundle.sh
scp -O -r firmware\update-bundle root@192.168.200.250:/tmp/leandns-upd
ssh root@192.168.200.250 "sh /tmp/leandns-upd/install-on-device.sh /tmp/leandns-upd"
```

Replace the IP with the device management address.

## From PC (Windows 11)

```bat
leandns-tool-windows-amd64.exe discover

leandns-tool-windows-amd64.exe set ^
  --token "token-shown-in-web-ui" ^
  --ip 192.168.34.250 ^
  --netmask 255.255.255.0 ^
  --gateway 192.168.34.1
```

Linux/macOS:

```bash
./leandns-tool-linux-amd64 discover
./leandns-tool-linux-amd64 set --token '...' --ip 192.168.34.250 --gateway 192.168.34.1
```

PC must be connected to the home main Wi-Fi or wired LAN. Verify that your firewall does not block UDP 37421 responses.

## Android

Project: [`android/leandns-tool/`](../android/leandns-tool/). Provides the same DISCOVER / SET as the PC tool.

### Build APK on Windows 11

1. Install Android Studio and prepare SDK 35
2. Open the `android\leandns-tool` folder
3. **Build → Build APK(s)** or:

```bat
cd C:\path\to\LeanDNS\android\leandns-tool
gradlew.bat assembleDebug
```

Output: `app\build\outputs\apk\debug\app-debug.apk`

Connect your phone to the home main Wi-Fi, then in the app tap **Discover** → select device → enter token if required → **Apply**.

## Web UI

The System screen manages immediate permanent LAN settings, confirmation of UDP temporary changes, UDP token requirements, and token display/regeneration.

## Notes

- Device-side daemon: C `cmd/leandns-discoverd/discoverd.c` → `./scripts/build-discoverd.sh` (mipsel softfloat musl).
- Android client: `android/leandns-tool/` (same protocol).
