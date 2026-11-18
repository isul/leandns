// LeanDNS LAN discovery / netcfg UDP agent for OpenWrt (mipsle softfloat).
package main

import (
	"crypto/subtle"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"
	"time"
)

const (
	port    = 37421
	magic   = "LEANDNS1"
	tokenFn = "/etc/leandns/udp.token"
)

type netInfo struct {
	IPAddr        string `json:"ipaddr"`
	Netmask       string `json:"netmask"`
	Gateway       string `json:"gateway"`
	MAC           string `json:"mac"`
	Version       string `json:"version"`
	Name          string `json:"name"`
	TokenRequired bool   `json:"token_required"`
}

type setReq struct {
	Token   string `json:"token"`
	IPAddr  string `json:"ipaddr"`
	Netmask string `json:"netmask"`
	Gateway string `json:"gateway"`
}

func main() {
	addr, err := net.ResolveUDPAddr("udp4", fmt.Sprintf(":%d", port))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	conn, err := net.ListenUDP("udp4", addr)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer conn.Close()
	_ = conn.SetReadBuffer(4096)

	buf := make([]byte, 4096)
	for {
		n, remote, err := conn.ReadFromUDP(buf)
		if err != nil || n == 0 {
			continue
		}
		msg := strings.TrimSpace(string(buf[:n]))
		reply := handle(msg)
		if reply == "" {
			continue
		}
		_, _ = conn.WriteToUDP([]byte(reply), remote)
	}
}

func handle(msg string) string {
	parts := strings.SplitN(msg, "|", 3)
	if len(parts) < 2 || parts[0] != magic {
		return ""
	}
	switch parts[1] {
	case "DISCOVER":
		info := readNet()
		b, _ := json.Marshal(info)
		return magic + "|DISCOVER_OK|" + string(b)
	case "SET":
		if len(parts) < 3 {
			return magic + `|SET_ERR|{"error":"missing body"}`
		}
		var req setReq
		if err := json.Unmarshal([]byte(parts[2]), &req); err != nil {
			return magic + `|SET_ERR|{"error":"bad json"}`
		}
		if tokenRequired() {
			tok, err := os.ReadFile(tokenFn)
			if err != nil {
				return magic + `|SET_ERR|{"error":"token not configured"}`
			}
			want := strings.TrimSpace(string(tok))
			if want == "" || subtle.ConstantTimeCompare([]byte(req.Token), []byte(want)) != 1 {
				return magic + `|SET_ERR|{"error":"unauthorized"}`
			}
		}
		if !validIPv4(req.IPAddr) || !validIPv4(req.Netmask) || !validIPv4(req.Gateway) {
			return magic + `|SET_ERR|{"error":"missing fields"}`
		}
		// Reply first, then apply after short delay in background so client gets ACK
		go func() {
			time.Sleep(300 * time.Millisecond)
			_ = exec.Command("/usr/libexec/leandns/apply-network.sh", req.IPAddr, req.Netmask, req.Gateway).Run()
		}()
		b, _ := json.Marshal(map[string]any{
			"ok":      true,
			"ipaddr":  req.IPAddr,
			"netmask": req.Netmask,
			"gateway": req.Gateway,
		})
		return magic + "|SET_OK|" + string(b)
	default:
		return ""
	}
}

func readNet() netInfo {
	info := netInfo{
		IPAddr:        uciGet("network.lan.ipaddr", "192.168.0.250"),
		Netmask:       uciGet("network.lan.netmask", "255.255.255.0"),
		Gateway:       uciGet("network.lan.gateway", "192.168.0.1"),
		Version:       "1.0.0",
		Name:          "LeanDNS",
		MAC:           "unknown",
		TokenRequired: tokenRequired(),
	}
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		n := iface.Name
		if n == "br-lan" || n == "lan" || strings.HasPrefix(n, "eth") {
			info.MAC = iface.HardwareAddr.String()
			if info.MAC != "" {
				break
			}
		}
	}
	return info
}

func tokenRequired() bool {
	return uciGet("leandns.main.udp_token_required", "1") != "0"
}

func validIPv4(s string) bool {
	ip := net.ParseIP(s)
	return ip != nil && ip.To4() != nil && !strings.ContainsAny(s, " \t")
}

func uciGet(key, def string) string {
	out, err := exec.Command("uci", "-q", "get", key).Output()
	if err != nil {
		return def
	}
	v := strings.TrimSpace(string(out))
	if v == "" {
		return def
	}
	return v
}
