#!/usr/bin/env python3
"""LeanDNS host mock API + static UI server (development only, not for the router)."""

from __future__ import annotations

import base64
import ipaddress
import json
import re
import secrets
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
WEB = ROOT / "web"
STATE_LOCK = threading.Lock()

DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\.?$"
)
IPV4_RE = re.compile(r"^(\d{1,3}\.){3}\d{1,3}$")


def valid_domain(d: str) -> bool:
    return bool(DOMAIN_RE.match(d)) and ".." not in d


def valid_ipv4(ip: str) -> bool:
    if not IPV4_RE.match(ip):
        return False
    return all(0 <= int(x) <= 255 for x in ip.split("."))


def valid_ipv6(ip: str) -> bool:
    try:
        ipaddress.IPv6Address(ip)
        return True
    except ValueError:
        return False


def valid_upstream(s: str) -> bool:
    host, _, port = s.partition("#")
    if port and not port.isdigit():
        return False
    if port and not (1 <= int(port) <= 65535):
        return False
    return valid_ipv4(host) or valid_ipv6(host) or valid_domain(host)


MOCK_RECENT_BLOCKS = [
    ("googleads.g.doubleclick.net", "ad", "192.168.1.34"),
    ("pagead2.googlesyndication.com", "ad", "192.168.1.12"),
    ("analytics.twitter.com", "track", "192.168.1.23"),
    ("ads.yahoo.com", "ad", "192.168.1.45"),
    ("securepubads.g.doubleclick.net", "ad", "192.168.1.34"),
    ("static.adsafeprotected.com", "track", "192.168.1.18"),
    ("adservice.google.com", "ad", "192.168.1.12"),
    ("pixel.facebook.com", "track", "192.168.1.23"),
    ("tpc.googlesyndication.com", "ad", "192.168.1.34"),
    ("cdn.ampproject.org", "block", "192.168.1.45"),
    ("ad.doubleclick.net", "ad", "192.168.1.12"),
    ("metrics.icloud.com", "track", "192.168.1.18"),
    ("ads-api.twitter.com", "ad", "192.168.1.23"),
    ("googleadservices.com", "ad", "192.168.1.34"),
    ("tracking.example.test", "track", "192.168.1.45"),
    ("partnerad.l.doubleclick.net", "ad", "192.168.1.12"),
    ("ads.linkedin.com", "ad", "192.168.1.18"),
    ("bat.bing.com", "track", "192.168.1.23"),
    ("adclick.g.doubleclick.net", "ad", "192.168.1.34"),
    ("cm.g.doubleclick.net", "ad", "192.168.1.45"),
]


def mock_block_stats():
    now = int(time.time())
    cur_min = now // 60
    trend_counts = [12, 18, 9, 27, 31, 22, 15, 40, 36, 24]
    trend = []
    for i, c in enumerate(trend_counts):
        m = cur_min - (9 - i)
        trend.append({"m": m, "c": c})
    recent = []
    for i, (domain, typ, client) in enumerate(MOCK_RECENT_BLOCKS[:20], start=1):
        ts = now - (i - 1) * 3
        recent.append(
            {
                "n": i,
                "domain": domain,
                "type": typ,
                "client": client,
                "ts": ts,
            }
        )
    return {
        "enabled": True,
        "paused": False,
        "recent_limit": 20,
        "count_1m": trend_counts[-1],
        "count_10m": sum(trend_counts),
        "count_today": 12482,
        "count_yesterday": 11550,
        "last_block_age_sec": 2,
        "last_block_domain": recent[0]["domain"] if recent else "",
        "trend": trend,
        "recent": recent,
    }


STATE = {
    "force_password_change": True,
    "sessions": set(),
    "dns": {
        "upstream": ["1.1.1.1", "8.8.8.8"],
        "cachesize": 1000,
        "internal_domain": "home.arpa",
        "ipv6_dns": False,
        "dns_test_host": "one.one.one.one",
    },
    "hosts": [
        {"hostname": "nas.home.arpa", "ip": "192.168.0.201"},
    ],
    "adblock_enabled": True,
    "adblock_available": True,
    "rule_count": 103761,
    "last_update": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "adblock_update_result": "unknown",
    "allow": ["example-allowed.test"],
    "block": ["ads.example.test"],
    "logs": [
        "leandns: mock server started",
        "dnsmasq: mock ready",
    ],
    "backup": None,
    "firmware_state": "idle",
    "firmware_image": None,
    "firmware_rebooting": False,
    "dnsmasq_running": True,
    "start": time.time(),
    "network": {
        "ipaddr": "192.168.0.250",
        "netmask": "255.255.255.0",
        "gateway": "192.168.0.1",
    },
    "udp_token": "demoToken0123456789abcd",
    "udp_set_enabled": True,
    "udp_token_required": True,
    "network_pending": None,
}


def require_auth(handler) -> bool:
    sid = handler.headers.get("X-Session", "")
    return sid in STATE["sessions"]


def status_payload():
    up = int(time.time() - STATE["start"])
    # Match the RT-AC750L-ish dashboard numbers from the design mock.
    mem_total = 58266
    mem_avail = 11674
    flash_total = 11878
    flash_free = 1740
    block_stats = mock_block_stats()
    return {
        "dnsmasq_running": STATE["dnsmasq_running"],
        "uptime_sec": up,
        "mem_total_kb": mem_total,
        "mem_available_kb": mem_avail,
        "cpu_percent": "unsupported",
        "flash_scope": "overlay",
        "flash_total_kb": flash_total,
        "flash_free_kb": flash_free,
        "cachesize": STATE["dns"]["cachesize"],
        "version": "1.0.1",
        "firmware": "OpenWrt 24.10.0",
        "cache_hit_rate": "unsupported",
        "blocked_query_count": block_stats["count_today"],
        "per_client_stats": "unsupported",
        "block_stats": block_stats,
        "upstream": STATE["dns"]["upstream"],
        "internal_domain": STATE["dns"]["internal_domain"],
        "dns_test_ok": STATE["dnsmasq_running"],
        "dns_test_latency_ms": 10,
        "dns_test_host": STATE["dns"]["dns_test_host"],
        "adblock": {
            "adblock_available": STATE["adblock_available"],
            "adblock_state": "enabled" if STATE["adblock_enabled"] else "disabled",
            "leandns_enabled": "1" if STATE["adblock_enabled"] else "0",
            "rule_count": STATE["rule_count"] if STATE["adblock_enabled"] else None,
            "last_update": STATE["last_update"] if STATE["adblock_enabled"] else None,
            "engine_state": "ok" if STATE["adblock_enabled"] else "stopped",
            "list_state": "applied" if STATE["adblock_enabled"] else "not_applied",
            "update_result": STATE["adblock_update_result"],
        },
    }


def handle_api(method: str, body: dict, authed: bool):
    if method == "login":
        user = body.get("username", "")
        pw = body.get("password", "")
        if user == "root" and pw == "wrong":
            return 403, {"error": "invalid credentials"}
        if not user or not pw:
            return 403, {"error": "invalid credentials"}
        # Accept any non-empty password except explicit "wrong" for tests;
        # document default demo: root / leandns
        if pw == "wrongpassword":
            return 403, {"error": "invalid credentials"}
        sid = secrets.token_hex(16)
        STATE["sessions"].add(sid)
        return 200, {"session": sid, "username": user}

    if method in ("ping", "auth_required"):
        if method == "ping":
            # Match device ACL: ping is unauthenticated (used while waiting for reboot).
            if STATE.get("firmware_rebooting"):
                return 503, {"ok": False, "error": "rebooting"}
            return 200, {
                "ok": True,
                "service": "leandns",
                "version": "1.0.1",
                "firmware": "OpenWrt 24.10.0 (mock)",
            }
        return 200, {"force_password_change": STATE["force_password_change"]}

    if method == "logout":
        return 200, {"ok": True}

    if not authed:
        return 401, {"error": "unauthorized"}

    if method == "status":
        return 200, status_payload()
    if method == "dns_get":
        return 200, dict(STATE["dns"])
    if method == "dns_set":
        ups = body.get("upstream", STATE["dns"]["upstream"])
        if not isinstance(ups, list) or any(not valid_upstream(u) for u in ups):
            return 200, {"ok": False, "error": "invalid upstream"}
        cache = int(body.get("cachesize", STATE["dns"]["cachesize"]))
        if cache < 0 or cache > 10000:
            return 200, {"ok": False, "error": "invalid cachesize"}
        domain = body.get("internal_domain", STATE["dns"]["internal_domain"])
        if not valid_domain(domain):
            return 200, {"ok": False, "error": "invalid domain"}
        STATE["dns"].update(
            {
                "upstream": ups,
                "cachesize": cache,
                "internal_domain": domain,
                "ipv6_dns": bool(body.get("ipv6_dns", False)),
                "dns_test_host": body.get("dns_test_host", STATE["dns"]["dns_test_host"]),
            }
        )
        return 200, {"ok": True}
    if method == "dns_test":
        host = body.get("host") or STATE["dns"]["dns_test_host"]
        if not isinstance(host, str) or not valid_domain(host):
            return 200, {"ok": False, "error": "Check the domain format."}
        addresses = [h["ip"] for h in STATE["hosts"] if h["hostname"] == host]
        if host in ("one.one.one.one", "example.com"):
            addresses = ["192.0.2.1"]
        if not STATE["dnsmasq_running"]:
            addresses = []
        return 200, {
            "ok": True,
            "dns_test_host": host,
            "dns_test_ok": bool(addresses),
            "dns_test_latency_ms": 0,
            "addresses": addresses,
        }
    if method == "dns_restart":
        return 200, {"ok": True}
    if method == "hosts_list":
        return 200, {"hosts": list(STATE["hosts"])}
    if method == "hosts_set":
        hosts = body.get("hosts", [])
        cleaned = []
        for h in hosts:
            hn = h.get("hostname", "")
            ip = h.get("ip", "")
            if not valid_domain(hn) or not (valid_ipv4(ip) or valid_ipv6(ip)):
                return 200, {"ok": False, "error": "invalid host record"}
            cleaned.append({"hostname": hn, "ip": ip})
        # dedupe
        merged = {}
        for h in cleaned:
            merged[h["hostname"]] = h
        STATE["hosts"] = list(merged.values())
        return 200, {"ok": True}
    if method == "adblock_status":
        return 200, status_payload()["adblock"]
    if method == "adblock_set":
        STATE["adblock_enabled"] = bool(body.get("enabled", True))
        return 200, {"ok": True}
    if method == "adblock_update":
        if not STATE["adblock_enabled"]:
            return 200, {"ok": False, "error": "Enable ad blocking first."}
        if body.get("force_fail"):
            STATE["adblock_update_result"] = "low_ram"
            return 200, {"ok": False, "error": "update failed; previous list retained"}
        STATE["last_update"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        STATE["rule_count"] = 85000
        STATE["adblock_update_result"] = "success"
        return 200, {"ok": True}
    if method == "lists_get":
        return 200, {"allow": list(STATE["allow"]), "block": list(STATE["block"])}
    if method == "lists_set":
        allow = []
        block = []
        for d in body.get("allow", []):
            if not valid_domain(d):
                return 200, {"ok": False, "error": "invalid allow domain"}
            allow.append(d)
        for d in body.get("block", []):
            if not valid_domain(d):
                return 200, {"ok": False, "error": "invalid block domain"}
            block.append(d)
        STATE["allow"] = sorted(set(allow))
        STATE["block"] = sorted(set(block))
        return 200, {"ok": True}
    if method == "system_info":
        return 200, status_payload()
    if method == "system_restart_services":
        return 200, {"ok": True}
    if method == "firmware_status":
        img = STATE.get("firmware_image")
        state = STATE.get("firmware_state", "idle")
        return 200, {
            "ok": True,
            "state": state,
            "image_present": bool(img),
            "verified": state == "verified" and bool(img),
            "image_kb": int((img or {}).get("kb", 0)),
            "mem_available_kb": 14852,
            "tmp_free_kb": 28088,
            "min_free_ram_kb": 8192,
            "upgrade_headroom_kb": 6144,
        }
    if method == "firmware_prepare":
        size = int(body.get("size") or 0)
        STATE["firmware_state"] = "prepared"
        STATE["firmware_image"] = None
        return 200, {
            "ok": True,
            "mem_available_kb": 20000,
            "tmp_free_kb": 28000,
            "min_free_ram_kb": 8192,
            "upgrade_headroom_kb": 6144,
            "image_path": "/tmp/leandns-sysupgrade.bin",
            "size": size,
        }
    if method == "firmware_upload":
        size = int(body.get("size") or 0)
        name = body.get("name") or "firmware.bin"
        if size < 1024 * 1024:
            return 200, {"ok": False, "error": "Image file is too small."}
        if "factory" in name.lower() or "sysupgrade" not in name.lower():
            return 200, {
                "ok": False,
                "error": "factory.bin is for Firmware Restoration. Use *-sysupgrade.bin.",
            }
        STATE["firmware_image"] = {"kb": (size + 1023) // 1024, "name": name}
        STATE["firmware_state"] = "uploaded"
        return 200, {"ok": True, "bytes": size, "path": "/tmp/leandns-sysupgrade.bin"}
    if method == "firmware_verify":
        if not STATE.get("firmware_image"):
            return 200, {"ok": False, "error": "No uploaded image."}
        STATE["firmware_state"] = "verified"
        return 200, {"ok": True, "verified": True, "image_kb": STATE["firmware_image"]["kb"]}
    if method == "firmware_abort":
        STATE["firmware_image"] = None
        STATE["firmware_state"] = "idle"
        return 200, {"ok": True}
    if method == "firmware_apply":
        if not STATE.get("firmware_image"):
            return 200, {"ok": False, "error": "No uploaded image."}
        if STATE.get("firmware_state") != "verified":
            return 200, {"ok": False, "error": "Image must pass verification first."}
        STATE["firmware_state"] = "applying"
        STATE["firmware_rebooting"] = True
        def _mock_fw_back():
            time.sleep(4)
            with STATE_LOCK:
                STATE["firmware_rebooting"] = False
                STATE["firmware_image"] = None
                STATE["firmware_state"] = "idle"
        threading.Thread(target=_mock_fw_back, daemon=True).start()
        return 200, {"ok": True, "started": True, "keep_settings": bool(body.get("keep_settings", True))}
    if method == "logs_get":
        n = min(int(body.get("lines", 100)), 500)
        return 200, {"lines": STATE["logs"][-n:]}
    if method == "logs_clear":
        STATE["logs"].clear()
        return 200, {"ok": True, "note": "log buffer clear attempted"}
    if method == "backup_export":
        payload = {
            "dns": STATE["dns"],
            "hosts": STATE["hosts"],
            "allow": STATE["allow"],
            "block": STATE["block"],
        }
        b64 = base64.b64encode(json.dumps(payload).encode()).decode()
        STATE["backup"] = payload
        return 200, {"ok": True, "filename": "leandns-backup.tar.gz", "data_base64": b64}
    if method == "backup_import":
        try:
            raw = base64.b64decode(body.get("data_base64", ""))
            data = json.loads(raw.decode())
            STATE["dns"] = data.get("dns", STATE["dns"])
            STATE["hosts"] = data.get("hosts", STATE["hosts"])
            STATE["allow"] = data.get("allow", STATE["allow"])
            STATE["block"] = data.get("block", STATE["block"])
            return 200, {"ok": True}
        except Exception as exc:  # noqa: BLE001
            return 200, {"ok": False, "error": f"import failed: {exc}"}
    if method == "password_changed":
        STATE["force_password_change"] = False
        return 200, {"ok": True}
    if method in ("network_get", "network_set", "network_confirm"):
        pending = STATE["network_pending"]
        if pending and time.monotonic() >= pending["deadline"]:
            STATE["network"] = pending["previous"]
            STATE["network_pending"] = pending = None
        if method == "network_get":
            return 200, {
                **STATE["network"],
                "pending_ip": STATE["network"]["ipaddr"] if pending else "",
                "pending_state": "ready" if pending else "",
            }
        if method == "network_confirm":
            if not pending:
                return 200, {"ok": False, "error": "No pending temporary settings to confirm."}
            STATE["network_pending"] = None
            return 200, {"ok": True}
        if pending:
            return 200, {"ok": False, "error": "Another network change is in progress."}
        network = {key: body.get(key, "") for key in ("ipaddr", "netmask", "gateway")}
        if not all(valid_ipv4(address) for address in network.values()):
            return 200, {"ok": False, "error": "Check IP address, subnet mask, and gateway."}
        # Web UI applies permanently; UDP-style pending is only simulated via network_pending.
        STATE["network"] = network
        STATE["network_pending"] = None
        return 200, {"ok": True, "applied": True}
    if method == "udp_token_get":
        STATE["udp_set_enabled"] = True
        result = {
            "port": 37421,
            "required": bool(STATE.get("udp_token_required", True)),
            "enabled": True,
        }
        if body.get("reveal") is True:
            result["token"] = STATE["udp_token"]
        return 200, result
    if method == "udp_token_set":
        if "required" in body:
            required = bool(body["required"])
        elif isinstance(body.get("enabled"), bool):
            # Legacy: enabled=false meant "no token", not "SET off".
            required = bool(body["enabled"])
        else:
            return 200, {"ok": False, "error": "required or enabled value is required."}
        STATE["udp_token_required"] = required
        STATE["udp_set_enabled"] = True
        return 200, {"ok": True, "required": required, "enabled": True}
    if method == "udp_token_regen":
        STATE["udp_token"] = secrets.token_hex(16)
        return 200, {"ok": True, "port": 37421}
    return 404, {"error": f"unknown method {method}"}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB), **kwargs)

    def log_message(self, fmt, *args):
        print("[mock]", fmt % args)

    def do_POST(self):
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/"):
            self.send_error(404)
            return
        method = parsed.path[len("/api/") :].strip("/")
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode() or "{}")
        except json.JSONDecodeError:
            body = {}
        authed = require_auth(self)
        with STATE_LOCK:
            code, payload = handle_api(method, body, authed)
        data = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.path = "/index.html"
        return super().do_GET()


def main():
    host, port = "127.0.0.1", 8765
    httpd = ThreadingHTTPServer((host, port), Handler)
    print(f"LeanDNS mock UI: http://{host}:{port}/")
    print("Demo login: any user / any password (except 'wrongpassword')")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
