English | [한국어](ko/architecture.md)

# LeanDNS Architecture

## Goal

Provide a DNS-only ad-blocking management system lighter than AdGuard Home on the ASUS RT-AC750L (OpenWrt `asus_rt-ac1200-v2`). Uses dnsmasq and adblock-lean without reimplementing a DNS engine.

## Components

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

## Design Decisions

| Decision | Detail |
|----------|--------|
| OS | OpenWrt 24.10.x |
| DNS | dnsmasq (UDP/TCP, cache) |
| Blocking | adblock-lean Mini |
| Web | uhttpd + static UI |
| API | rpcd/ubus + ucode |
| Auth | rpcd ubus `session` (no LuCI UI / luci-base) |
| DoH/DoT | Excluded in first version |
| Role | DNS-only LAN appliance (no DHCP/routing) |
| Firewall | firewall4/nft stack excluded (assumed behind main router on LAN) |

## Network Defaults

| Item | Default |
|------|---------|
| Management IP | 192.168.0.250/24 |
| Gateway | 192.168.0.1 |
| DHCP server | Disabled |
| DNS | TCP/UDP 53 |
| UI | LAN only |
| Internal domain | home.arpa |

The main router handles DHCP; LeanDNS handles DNS only. The main router's DNS setting is not changed automatically during installation.

## Configuration Storage

- `leandns` UCI: management options, cache, IPv6 toggle, query log options
- `dhcp` UCI: dnsmasq upstream, cache size, domain
- `/etc/leandns/hosts` or UCI host section: internal static records
- `/etc/adblock-lean/config`: Mini preset (`hagezi:pro.mini`)
- `/etc/leandns/allow.list`, `/etc/leandns/block.list`: custom allow/block

## Safe Apply

1. Back up relevant UCI/files before making changes.
2. Commit only after validation (domain, IP, numeric range) passes.
3. On service restart failure, restore backup and restart service.
4. No arbitrary shell execution API is provided.

## Statistics Policy

Only measurable values are displayed. Cache hit rate and per-client usage are shown as "not supported" in the UI if the engine does not provide them.

Block statistics (`block_stats`) are maintained **RAM-only** by parsing dnsmasq query logs from `/tmp` (cleared on reboot, never written to Flash). Recent blocks default to 20 entries; reduced to 10 when available RAM approaches `min_free_ram_kb`, and collection is paused when RAM drops below that threshold. tmpfs is cleared via pause/truncate immediately before adblock list updates, DNS re-apply, and package installation.
