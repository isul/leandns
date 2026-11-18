#!/usr/bin/env python3
"""API tests against in-process mock handlers (no server required)."""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host"))

import mock_server as ms  # noqa: E402


def reset():
    ms.STATE["sessions"].clear()
    ms.STATE["force_password_change"] = True
    ms.STATE["dns"] = {
        "upstream": ["1.1.1.1", "8.8.8.8"],
        "cachesize": 1000,
        "internal_domain": "home.arpa",
        "ipv6_dns": False,
        "dns_test_host": "one.one.one.one",
    }
    ms.STATE["hosts"] = [{"hostname": "nas.home.arpa", "ip": "192.168.0.201"}]
    ms.STATE["allow"] = []
    ms.STATE["block"] = []
    ms.STATE["adblock_enabled"] = True
    ms.STATE["logs"] = ["line1"]


class H:
    def __init__(self, sid=""):
        self.headers = {"X-Session": sid}


def call(method, body=None, sid=""):
    code, payload = ms.handle_api(method, body or {}, sid in ms.STATE["sessions"])
    return code, payload


def main():
    reset()
    fails = 0

    def check(cond, msg):
        nonlocal fails
        if not cond:
            print("FAIL:", msg)
            fails += 1
        else:
            print("ok:", msg)

    # auth failure
    code, p = call("status")
    check(code == 401, "unauth status rejected")

    code, p = call("login", {"username": "root", "password": "wrongpassword"})
    check(code == 403, "bad password rejected")

    code, p = call("login", {"username": "root", "password": "leandns"})
    check(code == 200 and "session" in p, "login ok")
    sid = p["session"]
    ms.STATE["sessions"].add(sid)  # already added inside handler

    code, p = ms.handle_api("status", {}, True)
    check(p.get("dnsmasq_running") is True, "status dns running")
    check(p.get("cache_hit_rate") == "unsupported", "no fake cache hit rate")

    code, p = ms.handle_api(
        "dns_set",
        {"upstream": ["not a domain!!!"], "cachesize": 100},
        True,
    )
    check(p.get("ok") is False, "invalid upstream rejected")

    code, p = ms.handle_api(
        "dns_set",
        {
            "upstream": ["9.9.9.9"],
            "cachesize": 500,
            "internal_domain": "home.arpa",
            "ipv6_dns": False,
            "dns_test_host": "one.one.one.one",
        },
        True,
    )
    check(p.get("ok") is True, "dns_set ok")

    code, p = ms.handle_api(
        "hosts_set",
        {"hosts": [{"hostname": "bad host", "ip": "1.2.3.4"}]},
        True,
    )
    check(p.get("ok") is False, "invalid host rejected")

    code, p = ms.handle_api(
        "hosts_set",
        {
            "hosts": [
                {"hostname": "nas.home.arpa", "ip": "192.168.0.201"},
                {"hostname": "server.home.arpa", "ip": "192.168.0.202"},
            ]
        },
        True,
    )
    check(p.get("ok") is True and len(ms.STATE["hosts"]) == 2, "hosts set")

    code, p = ms.handle_api(
        "lists_set",
        {"allow": ["ok.test", "ok.test"], "block": ["ads.test"]},
        True,
    )
    check(p.get("ok") is True and ms.STATE["allow"] == ["ok.test"], "lists dedupe")

    code, p = ms.handle_api("adblock_update", {}, True)
    check(p.get("ok") is True, "adblock update")

    code, p = ms.handle_api("adblock_update", {"force_fail": True}, True)
    check(p.get("ok") is False, "adblock update failure retained")

    code, p = ms.handle_api("backup_export", {}, True)
    check(p.get("ok") is True and p.get("data_base64"), "backup export")
    b64 = p["data_base64"]

    ms.STATE["hosts"] = []
    code, p = ms.handle_api("backup_import", {"data_base64": b64}, True)
    check(p.get("ok") is True and len(ms.STATE["hosts"]) == 2, "backup restore")

    code, p = ms.handle_api("logs_clear", {}, True)
    check(p.get("ok") is True and ms.STATE["logs"] == [], "logs clear")

    # config rollback simulation: invalid then previous dns remains if we reject
    before = dict(ms.STATE["dns"])
    code, p = ms.handle_api("dns_set", {"upstream": ["%%%"], "cachesize": 10}, True)
    check(p.get("ok") is False and ms.STATE["dns"]["upstream"] == before["upstream"], "dns rollback keep")

    if fails:
        print(f"mock_api: {fails} failures")
        sys.exit(1)
    print("mock_api: all ok")


if __name__ == "__main__":
    main()
