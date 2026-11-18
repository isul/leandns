#!/usr/bin/env python3
"""API tests against in-process mock handlers (no server required)."""

from __future__ import annotations

import base64
import json
import sys
import time
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
    check(bool(p.get("firmware")), "status includes firmware")
    check(bool(p.get("version")), "status includes version")
    bs = p.get("block_stats") or {}
    check(bs.get("enabled") is True, "block_stats enabled")
    check(isinstance(bs.get("count_today"), int), "block_stats count_today")
    check(isinstance(bs.get("recent"), list) and len(bs["recent"]) == 20, "block_stats recent 20")
    check(p.get("blocked_query_count") == bs.get("count_today"), "blocked_query_count matches today")

    code, p = ms.handle_api("ping", {}, True)
    check(p.get("firmware") and p.get("version"), "ping includes firmware/version")

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

    code, p = ms.handle_api("firmware_prepare", {"size": 3800000}, True)
    check(p.get("ok") is True, "firmware prepare")
    code, p = ms.handle_api(
        "firmware_upload", {"size": 3800000, "name": "openwrt-squashfs-factory.bin"}, True
    )
    check(p.get("ok") is False, "factory firmware rejected")
    code, p = ms.handle_api(
        "firmware_upload",
        {"size": 3800000, "name": "openwrt-squashfs-sysupgrade.bin"},
        True,
    )
    check(p.get("ok") is True, "firmware upload mock")
    code, p = ms.handle_api("firmware_verify", {}, True)
    check(p.get("ok") is True and p.get("verified") is True, "firmware verify")
    code, p = ms.handle_api("firmware_status", {}, True)
    check(p.get("image_present") is True and p.get("verified") is True, "firmware status verified")
    code, p = ms.handle_api("firmware_abort", {}, True)
    check(p.get("ok") is True, "firmware abort")

    code, p = ms.handle_api("adblock_update", {}, True)
    check(p.get("ok") is True, "adblock update")

    code, p = ms.handle_api("adblock_update", {"force_fail": True}, True)
    check(p.get("ok") is False, "adblock update failure retained")

    _, adblock = call("adblock_status", sid=sid)
    check(adblock["list_state"] == "applied" and adblock["update_result"] == "low_ram",
          "adblock update failure preserves applied list")

    _, probe = call("dns_test", {"host": "nas.home.arpa"}, sid)
    check(probe["addresses"] == ["192.168.0.201"] and probe["dns_test_latency_ms"] == 0,
          "test an entered domain and return its answers")
    _, probe = call("dns_test", {"host": "bad host"}, sid)
    check(probe["ok"] is False, "invalid probe domain rejected")

    _, token_info = call("udp_token_get", sid=sid)
    check(token_info["enabled"] is True and token_info["required"] is True and "token" not in token_info,
          "UDP SET on by default with token required and token hidden")
    _, token_info = call("udp_token_get", {"reveal": True}, sid)
    check(bool(token_info["token"]), "authenticated token reveal")
    _, off = call("udp_token_set", {"required": False}, sid)
    check(off["ok"] is True and off["required"] is False and off["enabled"] is True,
          "token can be disabled while UDP SET stays allowed")
    _, enabled = call("udp_token_set", {"required": True}, sid)
    check(enabled["enabled"] is True and enabled["required"] is True, "token can be required again")

    candidate = {"ipaddr": "192.168.10.250", "netmask": "255.255.255.0", "gateway": "192.168.10.1"}
    _, applied = call("network_set", candidate, sid)
    check(applied.get("ok") is True and applied.get("applied") is True, "network applied permanently")
    _, stored = call("network_get", sid=sid)
    check(not stored.get("pending_ip") and stored["ipaddr"] == candidate["ipaddr"],
          "web network_set saves without pending timeout")
    _, again = call("network_set", candidate, sid)
    check(again.get("ok") is True, "network can be reapplied when not pending")
    # UDP-style pending confirm path still requires auth and clears pending.
    ms.STATE["network_pending"] = {
        "previous": {"ipaddr": "192.168.0.250", "netmask": "255.255.255.0", "gateway": "192.168.0.1"},
        "deadline": time.monotonic() + 120,
    }
    ms.STATE["network"] = dict(candidate)
    code, _ = call("network_confirm")
    check(code == 401, "network confirmation requires authentication")
    _, confirmed = call("network_confirm", sid=sid)
    _, after = call("network_get", sid=sid)
    check(confirmed["ok"] is True and not after.get("pending_ip") and after["ipaddr"] == candidate["ipaddr"],
          "authenticated confirmation clears UDP pending")

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
