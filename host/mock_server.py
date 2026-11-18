#!/usr/bin/env python3
"""LeanDNS host mock API + static UI server (development only, not for the router)."""

from __future__ import annotations

import base64
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


def valid_upstream(s: str) -> bool:
    host, _, port = s.partition("#")
    if port and not port.isdigit():
        return False
    if port and not (1 <= int(port) <= 65535):
        return False
    return valid_ipv4(host) or valid_domain(host)


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
    "rule_count": 85000,
    "last_update": time.strftime("%Y-%m-%dT%H:%M:%S"),
    "allow": ["example-allowed.test"],
    "block": ["ads.example.test"],
    "logs": [
        "leandns: mock server started",
        "dnsmasq: mock ready",
    ],
    "backup": None,
    "dnsmasq_running": True,
    "start": time.time(),
    "network": {
        "ipaddr": "192.168.0.250",
        "netmask": "255.255.255.0",
        "gateway": "192.168.0.1",
    },
    "udp_token": "demoToken0123456789abcd",
    "udp_token_required": True,
}


def require_auth(handler) -> bool:
    sid = handler.headers.get("X-Session", "")
    return sid in STATE["sessions"]


def status_payload():
    up = int(time.time() - STATE["start"])
    return {
        "dnsmasq_running": STATE["dnsmasq_running"],
        "uptime_sec": up,
        "mem_total_kb": 65536,
        "mem_available_kb": 22000,
        "cpu_percent": "unsupported",
        "flash_total_kb": 16064,
        "flash_free_kb": 4200,
        "cachesize": STATE["dns"]["cachesize"],
        "cache_hit_rate": "unsupported",
        "blocked_query_count": "unsupported",
        "per_client_stats": "unsupported",
        "dns_test_ok": "true",
        "dns_test_latency_ms": "12",
        "dns_test_host": STATE["dns"]["dns_test_host"],
        "adblock": {
            "adblock_available": STATE["adblock_available"],
            "adblock_state": "enabled" if STATE["adblock_enabled"] else "disabled",
            "leandns_enabled": "1",
            "rule_count": str(STATE["rule_count"]),
            "last_update": STATE["last_update"],
            "status_file": "ok",
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
            if not authed:
                return 401, {"error": "unauthorized"}
            return 200, {"ok": True, "service": "leandns", "version": "1.0.0"}
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
        p = status_payload()
        p["ok"] = True
        return 200, p
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
            if not valid_domain(hn) or not valid_ipv4(ip):
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
        # simulate resource check
        if body.get("force_fail"):
            return 200, {"ok": False, "error": "update failed; previous list retained"}
        STATE["last_update"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        STATE["rule_count"] = 85000
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
    if method == "network_get":
        return 200, dict(STATE["network"])
    if method == "network_set":
        ipaddr = body.get("ipaddr", "")
        netmask = body.get("netmask", "")
        gateway = body.get("gateway", "")
        if not (valid_ipv4(ipaddr) and valid_ipv4(netmask) and valid_ipv4(gateway)):
            return 200, {"ok": False, "error": "missing fields"}
        STATE["network"] = {"ipaddr": ipaddr, "netmask": netmask, "gateway": gateway}
        return 200, {"ok": True}
    if method == "udp_token_get":
        return 200, {
            "token": STATE["udp_token"],
            "port": 37421,
            "required": STATE["udp_token_required"],
        }
    if method == "udp_token_set":
        if "required" not in body or not isinstance(body.get("required"), bool):
            return 200, {"ok": False, "error": "missing required"}
        STATE["udp_token_required"] = body["required"]
        return 200, {"ok": True, "required": STATE["udp_token_required"]}
    if method == "udp_token_regen":
        STATE["udp_token"] = secrets.token_hex(12)
        return 200, {"ok": True, "token": STATE["udp_token"], "port": 37421}
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
