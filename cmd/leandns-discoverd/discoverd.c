/* LeanDNS UDP discovery / netcfg agent — small musl softfloat binary */
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define PORT 37421
#define MAGIC "LEANDNS1"
#ifndef TOKEN_PATH
#define TOKEN_PATH "/etc/leandns/udp.token"
#endif
#define BUFSZ 2048
#define REPLY_MAX 1800

static void trim(char *s)
{
	size_t n = strlen(s);
	while (n && (s[n - 1] == '\n' || s[n - 1] == '\r' || s[n - 1] == ' ' || s[n - 1] == '\t'))
		s[--n] = 0;
}

static void uci_get(const char *key, char *out, size_t outsz, const char *def)
{
	char cmd[256];
	FILE *f;

	snprintf(cmd, sizeof(cmd), "uci -q get %s 2>/dev/null", key);
	f = popen(cmd, "r");
	if (!f) {
		snprintf(out, outsz, "%s", def);
		return;
	}
	if (!fgets(out, (int)outsz, f))
		snprintf(out, outsz, "%s", def);
	else
		trim(out);
	if (!out[0])
		snprintf(out, outsz, "%s", def);
	pclose(f);
}

/* Token check is on only when explicitly enabled (default off). */
static int udp_token_required(void)
{
	char v[16];
	uci_get("leandns.main.udp_token_required", v, sizeof(v), "0");
	return strcmp(v, "1") == 0;
}

/* SET is allowed only when explicitly enabled (default off in older configs). */
static int udp_set_enabled(void)
{
	char v[16];
	uci_get("leandns.main.udp_set_enabled", v, sizeof(v), "0");
	return strcmp(v, "1") == 0;
}

static int valid_ipv4(const char *s)
{
	int a, b, c, d;
	char tail;

	if (!s || !s[0])
		return 0;
	if (sscanf(s, "%d.%d.%d.%d%c", &a, &b, &c, &d, &tail) != 4)
		return 0;
	if (a < 0 || a > 255 || b < 0 || b > 255 || c < 0 || c > 255 || d < 0 || d > 255)
		return 0;
	return 1;
}

static int read_token(char *out, size_t outsz)
{
	FILE *f = fopen(TOKEN_PATH, "r");
	if (!f)
		return -1;
	if (!fgets(out, (int)outsz, f)) {
		fclose(f);
		return -1;
	}
	fclose(f);
	trim(out);
	return out[0] ? 0 : -1;
}

static void get_mac(char *out, size_t outsz)
{
	const char *names[] = { "br-lan", "eth0", "lan", NULL };
	char path[64], buf[64];
	FILE *f;
	int i;

	snprintf(out, outsz, "unknown");
	for (i = 0; names[i]; i++) {
		snprintf(path, sizeof(path), "/sys/class/net/%s/address", names[i]);
		f = fopen(path, "r");
		if (!f)
			continue;
		if (fgets(buf, sizeof(buf), f)) {
			trim(buf);
			if (buf[0]) {
				snprintf(out, outsz, "%s", buf);
				fclose(f);
				return;
			}
		}
		fclose(f);
	}
}

static void json_scrape(const char *body, const char *key, char *out, size_t outsz)
{
	char pat[64];
	const char *s;

	out[0] = 0;
	snprintf(pat, sizeof(pat), "\"%s\"", key);
	s = strstr(body, pat);
	if (!s)
		return;
	s += strlen(pat);
	while (*s == ' ' || *s == '\t' || *s == ':')
		s++;
	if (*s != '"')
		return;
	s++;
	snprintf(out, outsz, "%.*s", (int)(outsz - 1), s);
	{
		char *e = strchr(out, '"');
		if (e)
			*e = 0;
	}
}

static void reply_err(int sock, struct sockaddr_in *peer, socklen_t peerlen, const char *err)
{
	char reply[256];
	snprintf(reply, sizeof(reply), MAGIC "|SET_ERR|{\"error\":\"%s\"}", err);
	sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)peer, peerlen);
}

static void handle(int sock, struct sockaddr_in *peer, socklen_t peerlen, char *msg)
{
	char *p1;
	char reply[REPLY_MAX];
	char ip[64], mask[64], gw[64], mac[64], tok[128], want[128];
	char ip2[64], mask2[64], gw2[64];
	char cmd[512];
	FILE *f;
	char apply_out[REPLY_MAX];
	size_t nread;

	if (strncmp(msg, MAGIC "|", 9) != 0)
		return;
	p1 = msg + 9;

	if (!strncmp(p1, "DISCOVER", 8) && (p1[8] == 0 || p1[8] == '|')) {
		uci_get("network.lan.ipaddr", ip, sizeof(ip), "192.168.0.250");
		uci_get("network.lan.netmask", mask, sizeof(mask), "255.255.255.0");
		uci_get("network.lan.gateway", gw, sizeof(gw), "192.168.0.1");
		get_mac(mac, sizeof(mac));
		snprintf(reply, sizeof(reply),
			 MAGIC "|DISCOVER_OK|"
			 "{\"name\":\"LeanDNS\",\"version\":\"1.0.1\","
			 "\"ipaddr\":\"%s\",\"netmask\":\"%s\",\"gateway\":\"%s\",\"mac\":\"%s\","
			 "\"token_required\":%s,\"set_enabled\":%s}",
			 ip, mask, gw, mac,
			 udp_token_required() ? "true" : "false",
			 udp_set_enabled() ? "true" : "false");
		sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)peer, peerlen);
		return;
	}

	if (strncmp(p1, "SET|", 4) != 0)
		return;

	if (!udp_set_enabled()) {
		reply_err(sock, peer, peerlen, "remote IP changes disabled");
		return;
	}

	json_scrape(p1 + 4, "token", tok, sizeof(tok));
	json_scrape(p1 + 4, "ipaddr", ip2, sizeof(ip2));
	json_scrape(p1 + 4, "netmask", mask2, sizeof(mask2));
	json_scrape(p1 + 4, "gateway", gw2, sizeof(gw2));

	if (udp_token_required()) {
		if (read_token(want, sizeof(want)) != 0) {
			reply_err(sock, peer, peerlen, "token not configured");
			return;
		}
		if (!tok[0] || strcmp(tok, want) != 0) {
			reply_err(sock, peer, peerlen, "unauthorized");
			return;
		}
	}

	if (!valid_ipv4(ip2) || !valid_ipv4(mask2) || !valid_ipv4(gw2)) {
		reply_err(sock, peer, peerlen, "missing fields");
		return;
	}

	/* Permanent apply (same as web UI). Quote-safe: IPv4 dotted quads only. */
	snprintf(cmd, sizeof(cmd),
		 "/usr/libexec/leandns/apply-network.sh --web '%s' '%s' '%s'",
		 ip2, mask2, gw2);
	f = popen(cmd, "r");
	if (!f) {
		reply_err(sock, peer, peerlen, "could not apply LAN settings");
		return;
	}
	nread = fread(apply_out, 1, sizeof(apply_out) - 1, f);
	apply_out[nread] = 0;
	trim(apply_out);
	pclose(f);

	if (!strstr(apply_out, "\"ok\":true") && !strstr(apply_out, "\"ok\": true")) {
		if (apply_out[0]) {
			snprintf(reply, sizeof(reply), MAGIC "|SET_ERR|%s", apply_out);
			sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)peer, peerlen);
		} else {
			reply_err(sock, peer, peerlen, "could not apply LAN settings");
		}
		return;
	}

	snprintf(reply, sizeof(reply), MAGIC "|SET_OK|%s", apply_out);
	sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)peer, peerlen);
}

int main(void)
{
	int sock;
	struct sockaddr_in addr, peer;
	socklen_t peerlen;
	char buf[BUFSZ];
	int yes = 1;

	sock = socket(AF_INET, SOCK_DGRAM, 0);
	if (sock < 0)
		return 1;
	setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
	setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, sizeof(yes));
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(PORT);
	addr.sin_addr.s_addr = htonl(INADDR_ANY);
	if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0)
		return 1;

	for (;;) {
		peerlen = sizeof(peer);
		ssize_t n = recvfrom(sock, buf, sizeof(buf) - 1, 0,
				     (struct sockaddr *)&peer, &peerlen);
		if (n <= 0)
			continue;
		buf[n] = 0;
		handle(sock, &peer, peerlen, buf);
		while (waitpid(-1, NULL, WNOHANG) > 0) {
		}
	}
}
