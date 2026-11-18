/* LeanDNS UDP discovery/netcfg agent — tiny musl static binary */
#include <arpa/inet.h>
#include <net/if.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
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

static void trim(char *s) {
	size_t n = strlen(s);
	while (n && (s[n - 1] == '\n' || s[n - 1] == '\r' || s[n - 1] == ' '))
		s[--n] = 0;
}

static void uci_get(const char *key, char *out, size_t outsz, const char *def) {
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

/* Missing or any value other than 0 keeps the token check on. */
static int udp_token_required(void) {
	char v[16];
	uci_get("leandns.main.udp_token_required", v, sizeof(v), "1");
	return strcmp(v, "0") != 0;
}

static int valid_ipv4(const char *s) {
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

static int read_token(char *out, size_t outsz) {
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

static void get_mac(char *out, size_t outsz) {
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	struct ifreq ifr;
	const char *names[] = {"br-lan", "eth0", "lan", NULL};
	int i;
	snprintf(out, outsz, "unknown");
	if (fd < 0)
		return;
	for (i = 0; names[i]; i++) {
		memset(&ifr, 0, sizeof(ifr));
		strncpy(ifr.ifr_name, names[i], IFNAMSIZ - 1);
		if (ioctl(fd, SIOCGIFHWADDR, &ifr) == 0) {
			unsigned char *m = (unsigned char *)ifr.ifr_hwaddr.sa_data;
			snprintf(out, outsz, "%02x:%02x:%02x:%02x:%02x:%02x",
				 m[0], m[1], m[2], m[3], m[4], m[5]);
			break;
		}
	}
	close(fd);
}

static void handle(int sock, struct sockaddr_in *peer, socklen_t peerlen, char *msg) {
	char *p1, *p2;
	char reply[BUFSZ];
	char ip[64], mask[64], gw[64], mac[64], tok[128], want[128];
	char ip2[64], mask2[64], gw2[64], body[1024];

	if (strncmp(msg, MAGIC "|", 9) != 0)
		return;
	p1 = msg + 9;
	p2 = strchr(p1, '|');
	if (!strncmp(p1, "DISCOVER", 8) && (!p2 || p1[8] == 0 || p1[8] == '|')) {
		uci_get("network.lan.ipaddr", ip, sizeof(ip), "192.168.0.250");
		uci_get("network.lan.netmask", mask, sizeof(mask), "255.255.255.0");
		uci_get("network.lan.gateway", gw, sizeof(gw), "192.168.0.1");
		get_mac(mac, sizeof(mac));
		snprintf(reply, sizeof(reply),
			 MAGIC "|DISCOVER_OK|{\"name\":\"LeanDNS\",\"version\":\"1.0.0\","
			 "\"ipaddr\":\"%s\",\"netmask\":\"%s\",\"gateway\":\"%s\",\"mac\":\"%s\","
			 "\"token_required\":%s}",
			 ip, mask, gw, mac, udp_token_required() ? "true" : "false");
		sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)peer, peerlen);
		return;
	}
	if (strncmp(p1, "SET|", 4) != 0)
		return;
	p2 = p1 + 4;
	/* very small JSON field scrape */
	ip2[0] = mask2[0] = gw2[0] = tok[0] = 0;
	{
		const char *s;
		s = strstr(p2, "\"token\"");
		if (s && sscanf(s, "\"token\"%*[ \t:]\"%127[^\"]\"", tok) != 1)
			tok[0] = 0;
		s = strstr(p2, "\"ipaddr\"");
		if (s)
			sscanf(s, "\"ipaddr\"%*[ \t:]\"%63[^\"]\"", ip2);
		s = strstr(p2, "\"netmask\"");
		if (s)
			sscanf(s, "\"netmask\"%*[ \t:]\"%63[^\"]\"", mask2);
		s = strstr(p2, "\"gateway\"");
		if (s)
			sscanf(s, "\"gateway\"%*[ \t:]\"%63[^\"]\"", gw2);
	}
	if (udp_token_required()) {
		if (read_token(want, sizeof(want)) != 0 || !tok[0] || strcmp(tok, want) != 0) {
			snprintf(reply, sizeof(reply), MAGIC "|SET_ERR|{\"error\":\"unauthorized\"}");
			sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)peer, peerlen);
			return;
		}
	}
	if (!valid_ipv4(ip2) || !valid_ipv4(mask2) || !valid_ipv4(gw2)) {
		snprintf(reply, sizeof(reply), MAGIC "|SET_ERR|{\"error\":\"missing fields\"}");
		sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)peer, peerlen);
		return;
	}
	snprintf(reply, sizeof(reply),
		 MAGIC "|SET_OK|{\"ok\":true,\"ipaddr\":\"%s\",\"netmask\":\"%s\",\"gateway\":\"%s\"}",
		 ip2, mask2, gw2);
	sendto(sock, reply, strlen(reply), 0, (struct sockaddr *)peer, peerlen);

	if (fork() == 0) {
		usleep(300000);
		snprintf(body, sizeof(body), "/usr/libexec/leandns/apply-network.sh '%s' '%s' '%s'",
			 ip2, mask2, gw2);
		execl("/bin/sh", "sh", "-c", body, (char *)NULL);
		_exit(1);
	}
}

int main(void) {
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
		ssize_t n = recvfrom(sock, buf, sizeof(buf) - 1, 0, (struct sockaddr *)&peer, &peerlen);
		if (n <= 0)
			continue;
		buf[n] = 0;
		handle(sock, &peer, peerlen, buf);
		/* reap children */
		while (waitpid(-1, NULL, WNOHANG) > 0) {
		}
	}
}
