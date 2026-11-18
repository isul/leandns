#!/bin/sh
# Export / import LeanDNS configuration (UCI + lists). No firmware flash.

set -eu

EXPORT_DIR=/tmp/leandns-export
ARCHIVE=/tmp/leandns-backup.tar.gz

cmd_export() {
	rm -rf "$EXPORT_DIR"
	mkdir -p "$EXPORT_DIR"
	cp -a /etc/config/leandns "$EXPORT_DIR/" 2>/dev/null || true
	cp -a /etc/config/dhcp "$EXPORT_DIR/" 2>/dev/null || true
	cp -a /etc/leandns "$EXPORT_DIR/leandns-files" 2>/dev/null || true
	[ -f /etc/adblock-lean/config ] && mkdir -p "$EXPORT_DIR/adblock-lean" && \
		cp -a /etc/adblock-lean/config "$EXPORT_DIR/adblock-lean/" || true
	tar -czf "$ARCHIVE" -C "$EXPORT_DIR" .
	# Base64 for JSON transport
	if command -v base64 >/dev/null 2>&1; then
		b64="$(base64 "$ARCHIVE" | tr -d '\n')"
	else
		b64="$(busybox base64 "$ARCHIVE" | tr -d '\n')"
	fi
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

	rm -rf "$workdir"
	mkdir -p "$workdir"
	if command -v base64 >/dev/null 2>&1; then
		base64 -d "$raw" > "$bin" 2>/dev/null || busybox base64 -d "$raw" > "$bin"
	else
		busybox base64 -d "$raw" > "$bin"
	fi

	# Backup current before import
	/usr/libexec/leandns/apply-dns.sh --boot >/dev/null 2>&1 || true
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
