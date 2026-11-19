#!/bin/sh
# Export / import LeanDNS configuration (UCI + lists). No firmware flash.
# OpenWrt images often omit the BusyBox base64 applet; encode/decode portably.

set -eu

EXPORT_DIR=/tmp/leandns-export
ARCHIVE=/tmp/leandns-backup.tar.gz

# Returns 0 if external base64 encode works (stdout of "hi" is aGkg or aGk=).
_base64_bin_ok() {
	command -v base64 >/dev/null 2>&1 || return 1
	# Some PATH entries resolve to a missing BusyBox applet ("base64: applet not found").
	out="$(printf 'hi' | base64 2>/dev/null | tr -d '\n\r ')" || return 1
	case "$out" in
		aGk=|aGkg|aGk*) return 0 ;;
		*) return 1 ;;
	esac
}

_b64_encode_awk() {
	# hexdump decimal bytes -> awk RFC4648 (no line wraps)
	hexdump -v -e '1/1 "%u\n"' "$1" | awk '
	BEGIN { b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" }
	{ bytes[n++] = $1 + 0 }
	END {
		for (i = 0; i < n; i += 3) {
			b0 = bytes[i]
			b1 = (i + 1 < n) ? bytes[i + 1] : 0
			b2 = (i + 2 < n) ? bytes[i + 2] : 0
			nbits = (i + 2 < n) ? 3 : ((i + 1 < n) ? 2 : 1)
			val = b0 * 65536 + b1 * 256 + b2
			printf "%s", substr(b64, int(val / 262144) % 64 + 1, 1)
			printf "%s", substr(b64, int(val / 4096) % 64 + 1, 1)
			if (nbits >= 2) printf "%s", substr(b64, int(val / 64) % 64 + 1, 1); else printf "="
			if (nbits >= 3) printf "%s", substr(b64, val % 64 + 1, 1); else printf "="
		}
	}'
}

_b64_decode_awk() {
	# base64 text on stdin -> binary on stdout
	awk '
	BEGIN {
		b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		for (i = 1; i <= 64; i++) dec[substr(b64, i, 1)] = i - 1
	}
	{
		gsub(/[^A-Za-z0-9+\/=]/, "")
		line = line $0
	}
	END {
		n = length(line)
		for (i = 1; i <= n; i += 4) {
			c0 = substr(line, i, 1)
			c1 = substr(line, i + 1, 1)
			c2 = substr(line, i + 2, 1)
			c3 = substr(line, i + 3, 1)
			v0 = dec[c0]
			v1 = dec[c1]
			v2 = (c2 == "=" || c2 == "") ? -1 : dec[c2]
			v3 = (c3 == "=" || c3 == "") ? -1 : dec[c3]
			printf "%c", int(v0 * 4 + int(v1 / 16))
			if (v2 >= 0) printf "%c", int((v1 % 16) * 16 + int(v2 / 4))
			if (v3 >= 0) printf "%c", int((v2 % 4) * 64 + v3)
		}
	}'
}

b64_encode_file() {
	src="$1"
	if _base64_bin_ok; then
		base64 "$src" 2>/dev/null | tr -d '\n\r' && return 0
	fi
	if command -v openssl >/dev/null 2>&1; then
		openssl enc -base64 -A -in "$src" 2>/dev/null && return 0
	fi
	_b64_encode_awk "$src"
}

b64_decode_to_file() {
	# stdin base64 -> "$1" binary
	dst="$1"
	if _base64_bin_ok; then
		base64 -d > "$dst" 2>/dev/null && return 0
		# GNU uses -d; some use --decode; retry via openssl/awk below
	fi
	if command -v openssl >/dev/null 2>&1; then
		openssl enc -base64 -d -A > "$dst" 2>/dev/null && return 0
	fi
	_b64_decode_awk > "$dst"
}

cmd_export() {
	rm -rf "$EXPORT_DIR"
	mkdir -p "$EXPORT_DIR"
	cp -a /etc/config/leandns "$EXPORT_DIR/" 2>/dev/null || true
	cp -a /etc/config/dhcp "$EXPORT_DIR/" 2>/dev/null || true
	cp -a /etc/leandns "$EXPORT_DIR/leandns-files" 2>/dev/null || true
	[ -f /etc/adblock-lean/config ] && mkdir -p "$EXPORT_DIR/adblock-lean" && \
		cp -a /etc/adblock-lean/config "$EXPORT_DIR/adblock-lean/" || true
	tar -czf "$ARCHIVE" -C "$EXPORT_DIR" .
	[ -s "$ARCHIVE" ] || {
		echo '{"ok":false,"error":"backup archive empty"}'
		return 1
	}
	b64="$(b64_encode_file "$ARCHIVE")"
	b64="$(printf '%s' "$b64" | tr -d '\n\r')"
	[ -n "$b64" ] || {
		echo '{"ok":false,"error":"base64 encode failed"}'
		return 1
	}
	printf '{"ok":true,"filename":"leandns-backup.tar.gz","data_base64":"%s"}\n' "$b64"
}

cmd_import() {
	# Expect base64 on stdin or as file path arg2
	infile="${2:-}"
	raw=/tmp/leandns-import.b64
	bin=/tmp/leandns-import.tar.gz
	workdir=/tmp/leandns-import

	if [ -n "$infile" ] && [ -f "$infile" ]; then
		cp "$infile" "$raw"
	else
		cat > "$raw"
	fi

	[ -s "$raw" ] || {
		echo '{"ok":false,"error":"missing data_base64"}'
		return 1
	}

	rm -rf "$workdir"
	mkdir -p "$workdir"
	# strip accidental JSON wrapper from older broken exports
	if grep -q '"data_base64"' "$raw" 2>/dev/null; then
		sed -n 's/.*"data_base64"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$raw" > "$raw.extract"
		mv "$raw.extract" "$raw"
	fi
	tr -d '\n\r \t' < "$raw" > "$raw.clean"
	mv "$raw.clean" "$raw"

	b64_decode_to_file "$bin" < "$raw"
	[ -s "$bin" ] || {
		echo '{"ok":false,"error":"base64 decode failed"}'
		return 1
	}

	# Backup current before import
	/usr/libexec/leandns/apply-dns.sh --boot >/dev/null 2>&1 || true
	mkdir -p /var/lib/leandns/backup
	cp -a /etc/config/leandns /var/lib/leandns/backup/leandns.preimport 2>/dev/null || true
	cp -a /etc/config/dhcp /var/lib/leandns/backup/dhcp.preimport 2>/dev/null || true

	tar -xzf "$bin" -C "$workdir"
	[ -f "$workdir/leandns" ] && cp -a "$workdir/leandns" /etc/config/leandns
	[ -f "$workdir/dhcp" ] && cp -a "$workdir/dhcp" /etc/config/dhcp
	if [ -d "$workdir/leandns-files" ]; then
		mkdir -p /etc/leandns
		cp -a "$workdir/leandns-files/." /etc/leandns/
	fi
	if [ -f "$workdir/adblock-lean/config" ]; then
		mkdir -p /etc/adblock-lean
		cp -a "$workdir/adblock-lean/config" /etc/adblock-lean/config
	fi

	uci commit leandns 2>/dev/null || true
	uci commit dhcp 2>/dev/null || true

	if /usr/libexec/leandns/apply-dns.sh --apply; then
		/usr/libexec/leandns/adblock-ctl.sh sync-lists >/dev/null 2>&1 || true
		echo '{"ok":true}'
	else
		# rollback
		[ -f /var/lib/leandns/backup/leandns.preimport ] && \
			cp -a /var/lib/leandns/backup/leandns.preimport /etc/config/leandns
		[ -f /var/lib/leandns/backup/dhcp.preimport ] && \
			cp -a /var/lib/leandns/backup/dhcp.preimport /etc/config/dhcp
		/usr/libexec/leandns/apply-dns.sh --rollback >/dev/null 2>&1 || true
		echo '{"ok":false,"error":"import apply failed; restored previous"}'
		return 1
	fi
}

case "${1:-}" in
	export) cmd_export ;;
	import) cmd_import "$@" ;;
	*)
		echo "usage: $0 export|import [file]" >&2
		exit 2
		;;
esac
