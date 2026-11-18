// LeanDNS PC-side UDP discovery / LAN netcfg tool (Windows · Linux · macOS).
// Protocol: LEANDNS1 on UDP/37421 — same L2 as the appliance even if subnets differ.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"strings"
	"time"
)

const (
	port  = 37421
	magic = "LEANDNS1"
)

type discoverInfo struct {
	Name          string `json:"name"`
	Version       string `json:"version"`
	IPAddr        string `json:"ipaddr"`
	Netmask       string `json:"netmask"`
	Gateway       string `json:"gateway"`
	MAC           string `json:"mac"`
	TokenRequired *bool  `json:"token_required"`
}

type setBody struct {
	Token   string `json:"token"`
	IPAddr  string `json:"ipaddr"`
	Netmask string `json:"netmask"`
	Gateway string `json:"gateway"`
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "discover":
		fs := flag.NewFlagSet("discover", flag.ExitOnError)
		wait := fs.Duration("wait", 2*time.Second, "listen window after broadcast")
		_ = fs.Parse(os.Args[2:])
		err = cmdDiscover(*wait)
	case "set":
		fs := flag.NewFlagSet("set", flag.ExitOnError)
		token := fs.String("token", "", "UDP token (omit when the device has token check off)")
		ip := fs.String("ip", "", "new LAN IP")
		netmask := fs.String("netmask", "255.255.255.0", "new netmask")
		gateway := fs.String("gateway", "", "new gateway")
		wait := fs.Duration("wait", 3*time.Second, "listen window after SET")
		_ = fs.Parse(os.Args[2:])
		if *ip == "" || *gateway == "" {
			fmt.Fprintln(os.Stderr, "set requires --ip and --gateway")
			fs.Usage()
			os.Exit(2)
		}
		err = cmdSet(*token, *ip, *netmask, *gateway, *wait)
	case "-h", "--help", "help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `LeanDNS UDP discovery / netcfg tool

Usage:
  leandns-tool discover [--wait 2s]
  leandns-tool set [--token TOKEN] --ip IP --gateway GW [--netmask 255.255.255.0]

Device daemon listens on UDP/%d (%s).
SET needs --token only when the device setting "IP 변경에 토큰 필요" is on.
When that setting is off, omit --token.
`, port, magic)
}

func cmdDiscover(wait time.Duration) error {
	fmt.Printf("Broadcasting DISCOVER on UDP/%d ...\n", port)
	replies, err := sendRecv(magic+"|DISCOVER", wait)
	if err != nil {
		return err
	}
	if len(replies) == 0 {
		return fmt.Errorf("장치 응답 없음. 같은 스위치/공유기 LAN에 PC를 연결했는지 확인하세요")
	}
	for _, r := range replies {
		parts := strings.SplitN(r.text, "|", 3)
		if len(parts) >= 3 && parts[1] == "DISCOVER_OK" {
			var info discoverInfo
			if json.Unmarshal([]byte(parts[2]), &info) != nil {
				fmt.Printf("%s: %s\n", r.from, r.text)
				continue
			}
			fmt.Println("---")
			fmt.Printf("from:     %s\n", r.from)
			fmt.Printf("name:     %s\n", info.Name)
			fmt.Printf("ipaddr:   %s\n", info.IPAddr)
			fmt.Printf("netmask:  %s\n", info.Netmask)
			fmt.Printf("gateway:  %s\n", info.Gateway)
			fmt.Printf("mac:      %s\n", info.MAC)
			fmt.Printf("version:  %s\n", info.Version)
			switch {
			case info.TokenRequired == nil:
				fmt.Printf("token:    unknown (assume required)\n")
			case *info.TokenRequired:
				fmt.Printf("token:    required\n")
			default:
				fmt.Printf("token:    off (set without --token)\n")
			}
			fmt.Printf("ui:       http://%s/leandns/\n", info.IPAddr)
			continue
		}
		fmt.Printf("%s: %s\n", r.from, r.text)
	}
	return nil
}

func cmdSet(token, ip, netmask, gateway string, wait time.Duration) error {
	body, err := json.Marshal(setBody{
		Token:   token,
		IPAddr:  ip,
		Netmask: netmask,
		Gateway: gateway,
	})
	if err != nil {
		return err
	}
	payload := magic + "|SET|" + string(body)
	fmt.Printf("Sending SET -> %s / %s gw %s\n", ip, netmask, gateway)
	replies, err := sendRecv(payload, wait)
	if err != nil {
		return err
	}
	if len(replies) == 0 {
		return fmt.Errorf("응답 없음 (토큰·방화벽·L2 연결 확인)")
	}
	ok := false
	for _, r := range replies {
		parts := strings.SplitN(r.text, "|", 3)
		if len(parts) >= 3 && parts[1] == "SET_OK" {
			fmt.Printf("OK from %s: %s\n", r.from, parts[2])
			fmt.Printf("수 초 후 http://%s/leandns/ 로 접속하세요.\n", ip)
			ok = true
			continue
		}
		fmt.Printf("%s: %s\n", r.from, r.text)
	}
	if !ok {
		return fmt.Errorf("SET 실패")
	}
	return nil
}

type reply struct {
	from string
	text string
}

func sendRecv(payload string, wait time.Duration) ([]reply, error) {
	conn, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4zero, Port: 0})
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	_ = conn.SetReadBuffer(4096)

	dst := &net.UDPAddr{IP: net.IPv4bcast, Port: port}
	if _, err := conn.WriteToUDP([]byte(payload), dst); err != nil {
		return nil, fmt.Errorf("broadcast send: %w", err)
	}

	deadline := time.Now().Add(wait)
	_ = conn.SetReadDeadline(deadline)
	var out []reply
	seen := map[string]struct{}{}
	buf := make([]byte, 4096)
	for {
		n, addr, err := conn.ReadFromUDP(buf)
		if err != nil {
			if ne, ok := err.(net.Error); ok && ne.Timeout() {
				break
			}
			break
		}
		text := strings.TrimSpace(string(buf[:n]))
		key := addr.IP.String() + "|" + text
		if _, dup := seen[key]; dup {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, reply{from: addr.IP.String(), text: text})
		_ = conn.SetReadDeadline(deadline)
	}
	return out, nil
}
