#!/usr/bin/env python3
"""LeanDNS discovery / LAN netcfg tool (Windows · Linux).

Uses UDP broadcast on port 37421 (same L2 even if IP subnet differs).
SET needs the device UDP token only when the Web UI setting is on.
When "IP 변경에 토큰 필요" is off, omit --token.
"""

from __future__ import annotations

import argparse
import json
import socket
import sys
import time

PORT = 37421
MAGIC = "LEANDNS1"
TIMEOUT = 2.0


def broadcast_addrs() -> list[str]:
    return ["255.255.255.255"]


def send_recv(payload: str, wait: float = TIMEOUT) -> list[tuple[str, str]]:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.settimeout(0.3)
    try:
        sock.bind(("", 0))
    except OSError:
        pass
    data = payload.encode()
    for bcast in broadcast_addrs():
        try:
            sock.sendto(data, (bcast, PORT))
        except OSError as exc:
            print(f"send {bcast}: {exc}", file=sys.stderr)
    end = time.time() + wait
    found: list[tuple[str, str]] = []
    seen = set()
    while time.time() < end:
        try:
            msg, addr = sock.recvfrom(4096)
        except socket.timeout:
            continue
        except OSError:
            break
        text = msg.decode(errors="replace").strip()
        key = (addr[0], text)
        if key in seen:
            continue
        seen.add(key)
        found.append((addr[0], text))
    sock.close()
    return found


def cmd_discover(_: argparse.Namespace) -> int:
    print(f"Broadcasting DISCOVER on UDP/{PORT} ...")
    replies = send_recv(f"{MAGIC}|DISCOVER")
    if not replies:
        print("장치 응답 없음. 같은 스위치/공유기 LAN에 PC를 연결했는지 확인하세요.")
        return 1
    for src, text in replies:
        parts = text.split("|", 2)
        if len(parts) >= 3 and parts[1] == "DISCOVER_OK":
            try:
                info = json.loads(parts[2])
            except json.JSONDecodeError:
                print(f"{src}: {text}")
                continue
            print("---")
            print(f"from:     {src}")
            print(f"name:     {info.get('name')}")
            print(f"ipaddr:   {info.get('ipaddr')}")
            print(f"netmask:  {info.get('netmask')}")
            print(f"gateway:  {info.get('gateway')}")
            print(f"mac:      {info.get('mac')}")
            print(f"version:  {info.get('version')}")
            if "token_required" not in info:
                print("token:    unknown (assume required)")
            elif info.get("token_required"):
                print("token:    required")
            else:
                print("token:    off (set without --token)")
            print(f"ui:       http://{info.get('ipaddr')}/leandns/")
        else:
            print(f"{src}: {text}")
    return 0


def cmd_set(args: argparse.Namespace) -> int:
    body = {
        "token": args.token or "",
        "ipaddr": args.ip,
        "netmask": args.netmask,
        "gateway": args.gateway,
    }
    payload = f"{MAGIC}|SET|{json.dumps(body, separators=(',', ':'))}"
    print(f"Sending SET -> {args.ip} / {args.netmask} gw {args.gateway}")
    replies = send_recv(payload, wait=3.0)
    if not replies:
        print("응답 없음 (토큰·방화벽·L2 연결 확인)")
        return 1
    rc = 1
    for src, text in replies:
        parts = text.split("|", 2)
        if len(parts) >= 3 and parts[1] == "SET_OK":
            print(f"OK from {src}: {parts[2]}")
            print(f"수 초 후 http://{args.ip}/leandns/ 로 접속하세요.")
            rc = 0
        else:
            print(f"{src}: {text}")
    return rc


def main() -> int:
    p = argparse.ArgumentParser(description="LeanDNS UDP discovery / netcfg tool")
    sub = p.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("discover", help="Find LeanDNS on local LAN (broadcast)")
    d.set_defaults(func=cmd_discover)

    s = sub.add_parser("set", help="Set IP/netmask/gateway via UDP")
    s.add_argument("--token", default="", help="UDP token; omit when the device token check is off")
    s.add_argument("--ip", required=True)
    s.add_argument("--netmask", default="255.255.255.0")
    s.add_argument("--gateway", required=True)
    s.set_defaults(func=cmd_set)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
