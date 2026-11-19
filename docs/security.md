English | [한국어](ko/security.md)

# Security

## Authentication

- The management UI cannot be used without authentication.
- On the device, the luci-base/`session` ubus login is reused.
- The host mock is for development only and is not installed on the device.
- The "no root password" warning on the login screen is determined by the presence of a root hash in `/etc/shadow`. (`leandns.main.force_password_change` is a cache; even if UCI is not updated via SSH `passwd`, the shadow check causes the warning to disappear.)

## Network Exposure

- UI: Assumes LAN access only (`uhttpd` rfc1918_filter).
- DNS: Default configuration allows only local subnet queries via `localservice`.
- DNS recursion is not exposed to the internet.

## API Protection

- rpcd ACL (`leandns.json`) separates read/write per method.
- No arbitrary shell execution API. Only approved helpers are called.
- Input validation for domains, IPs, cache sizes, etc. (`leandns-validate`).
- Web UI primarily uses `textContent` to reduce XSS surface.
- External blocklists are filtered to domain lines only during the sync stage.

## CSRF

- A ubus session token is required for requests. Cannot be called from a browser site without a session.
- Mock mode uses the `X-Session` header.

## Backup Files

- Exported files contain DNS/hosts/list configuration. Store securely.
- Firmware upgrades can only be performed by an authenticated admin; the image is stored in `/tmp` only once.
- No automatic download or auto-flash. Apply only after explicit confirmation in the UI.

## Query Logging

- Disabled by default. When enabled, the UI help text notifies that personal data (visited domains) may be logged.
