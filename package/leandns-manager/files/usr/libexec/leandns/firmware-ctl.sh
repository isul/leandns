#!/bin/sh
# LeanDNS firmware upgrade helpers. Image lives only on /tmp (RAM).
# Does not flash until apply is called explicitly.

set -eu

IMG=/tmp/leandns-sysupgrade.bin
LOCK=/tmp/leandns-fw.lock
STATE=/var/lib/leandns/firmware.state
LOG=/tmp/leandns-firmware.log

mkdir -p /var/lib/leandns

log() {
	logger -t leandns-firmware "$*"
	printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo now)" "$*" >> "$LOG" 2>/dev/null || true
}

json_err() {
	printf '{"ok":false,"error":"%s"}\n' "$1"
}

free_ram_kb() {
	awk '/^MemAvailable:/ {print $2; found=1} END {if (!found) print 0}' /proc/meminfo 2>/dev/null || echo 0
}

tmp_free_kb() {
	df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo 0
}

min_ram_kb() {
	v="$(uci -q get leandns.main.min_free_ram_kb 2>/dev/null || true)"
	echo "${v:-8192}"
}

# Extra headroom beyond the image itself for sysupgrade + kernel.
upgrade_headroom_kb() {
	v="$(uci -q get leandns.main.upgrade_headroom_kb 2>/dev/null || true)"
	echo "${v:-6144}"
}

write_state() {
	printf '%s\n' "$1" > "$STATE"
}

img_size_kb() {
	if [ -f "$IMG" ]; then
		sz="$(wc -c < "$IMG" 2>/dev/null | tr -d ' ')"
		echo $(( (sz + 1023) / 1024 ))
	else
		echo 0
	fi
}

pause_helpers() {
	[ -x /usr/libexec/leandns/stats-ctl.sh ] && /usr/libexec/leandns/stats-ctl.sh pause >/dev/null 2>&1 || true
}

resume_helpers() {
	[ -x /usr/libexec/leandns/stats-ctl.sh ] && /usr/libexec/leandns/stats-ctl.sh resume >/dev/null 2>&1 || true
}

# Drop blocklist from RAM so /tmp upload has margin; device reboots on success.
unload_adblock() {
	if [ -x /etc/init.d/adblock-lean ]; then
		/etc/init.d/adblock-lean stop >/dev/null 2>&1 || true
	fi
	# Remove expanded list copies on tmpfs if present.
	rm -f /tmp/dnsmasq.d/abl-blocklist /tmp/dnsmasq.d/abl-conf-script /tmp/dnsmasq.d/.abl-extract_blocklist 2>/dev/null || true
	rm -f /var/run/adblock-lean/abl-blocklist.gz /var/run/adblock-lean/abl-blocklist.zst 2>/dev/null || true
	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
	sync
}

cmd_status() {
	ram="$(free_ram_kb)"
	tmp="$(tmp_free_kb)"
	min="$(min_ram_kb)"
	head="$(upgrade_headroom_kb)"
	img_kb="$(img_size_kb)"
	st="$(cat "$STATE" 2>/dev/null || echo idle)"
	has=false
	verified=false
	[ -f "$IMG" ] && [ "$img_kb" -gt 0 ] && has=true
	[ "$st" = verified ] && [ "$has" = true ] && verified=true
	printf '{"ok":true,"state":"%s","image_present":%s,"verified":%s,"image_kb":%s,"mem_available_kb":%s,"tmp_free_kb":%s,"min_free_ram_kb":%s,"upgrade_headroom_kb":%s}\n' \
		"$st" "$has" "$verified" "$img_kb" "$ram" "$tmp" "$min" "$head"
}

cmd_prepare() {
	# expected_bytes optional in argv $2
	expect="${1:-0}"
	case "$expect" in ''|*[!0-9]*) expect=0 ;; esac

	pause_helpers
	unload_adblock
	# Give kernel a moment to reclaim after dnsmasq restart.
	sleep 1

	ram="$(free_ram_kb)"
	tmp="$(tmp_free_kb)"
	min="$(min_ram_kb)"
	head="$(upgrade_headroom_kb)"

	if [ "$ram" -lt "$min" ]; then
		write_state error:low_ram
		resume_helpers
		json_err "Insufficient available RAM (${ram}KB < ${min}KB)."
		return 0
	fi

	need_tmp=512
	need_ram="$head"
	if [ "$expect" -gt 0 ]; then
		expect_kb=$(( (expect + 1023) / 1024 ))
		need_tmp=$(( expect_kb + 512 ))
		need_ram=$(( expect_kb + head ))
	fi

	if [ "$tmp" -lt "$need_tmp" ]; then
		write_state error:low_tmp
		resume_helpers
		json_err "Insufficient /tmp space (${tmp}KB < ${need_tmp}KB)."
		return 0
	fi

	if [ "$expect" -gt 0 ] && [ "$ram" -lt "$need_ram" ]; then
		write_state error:low_ram
		resume_helpers
		json_err "Insufficient RAM for upload/upgrade (${ram}KB < ${need_ram}KB)."
		return 0
	fi

	rm -f "$IMG"
	write_state prepared
	log "prepare ok ram=${ram}KB tmp=${tmp}KB expect=${expect}"
	printf '{"ok":true,"mem_available_kb":%s,"tmp_free_kb":%s,"min_free_ram_kb":%s,"upgrade_headroom_kb":%s,"image_path":"%s"}\n' \
		"$ram" "$tmp" "$min" "$head" "$IMG"
}

cmd_abort() {
	rm -f "$IMG"
	rmdir "$LOCK" 2>/dev/null || true
	write_state idle
	resume_helpers
	# Best-effort restore adblock if it was enabled.
	if [ "$(uci -q get leandns.main.enabled 2>/dev/null || echo 0)" = 1 ] && [ -x /usr/libexec/leandns/adblock-ctl.sh ]; then
		/usr/libexec/leandns/adblock-ctl.sh enable >/dev/null 2>&1 || true
	fi
	log "abort"
	echo '{"ok":true}'
}

test_err_message() {
	# Prefer a clear hint when users upload factory.bin (no OpenWrt metadata).
	if grep -qiE 'metadata not present|Image metadata not present' "$LOG.test" 2>/dev/null; then
		printf '%s' "factory images cannot be used for web upgrade. Use a .bin whose name contains sysupgrade."
		return
	fi
	if grep -qiE 'invalid|not supported|device' "$LOG.test" 2>/dev/null; then
		msg="$(tail -n 4 "$LOG.test" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')"
		printf '%s' "Image is not suitable for this device. ${msg}"
		return
	fi
	msg="$(tail -n 4 "$LOG.test" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g')"
	printf '%s' "Image verification failed. ${msg}"
}

cmd_verify() {
	if [ ! -f "$IMG" ]; then
		json_err "No uploaded image."
		return 0
	fi
	sz="$(wc -c < "$IMG" | tr -d ' ')"
	if [ "$sz" -lt 1048576 ]; then
		rm -f "$IMG"
		write_state error:invalid_image
		json_err "Image file is too small."
		return 0
	fi
	write_state testing
	log "sysupgrade --test begin size=${sz}"
	if ! /sbin/sysupgrade --test "$IMG" >"$LOG.test" 2>&1; then
		err="$(test_err_message)"
		rm -f "$IMG"
		write_state error:invalid_image
		log "sysupgrade --test failed: ${err}"
		json_err "$err"
		return 0
	fi
	write_state verified
	log "sysupgrade --test ok"
	printf '{"ok":true,"verified":true,"image_kb":%s}\n' "$(( (sz + 1023) / 1024 ))"
}

cmd_apply() {
	keep="${1:-true}"
	if [ ! -f "$IMG" ]; then
		json_err "No uploaded image."
		return 0
	fi
	sz="$(wc -c < "$IMG" | tr -d ' ')"
	if [ "$sz" -lt 1048576 ]; then
		json_err "Image file is too small."
		return 0
	fi

	ram="$(free_ram_kb)"
	head="$(upgrade_headroom_kb)"
	# Image already occupies RAM; MemAvailable should still cover headroom.
	if [ "$ram" -lt "$head" ]; then
		json_err "Insufficient available RAM to run sysupgrade (${ram}KB < ${head}KB)."
		return 0
	fi

	# Re-test immediately before flash (upload may have skipped verify).
	write_state testing
	log "sysupgrade --test before apply size=${sz}"
	if ! /sbin/sysupgrade --test "$IMG" >"$LOG.test" 2>&1; then
		err="$(test_err_message)"
		write_state error:invalid_image
		json_err "$err"
		return 0
	fi

	write_state applying
	keep_json=true
	sysupgrade_opts=
	if [ "$keep" = "false" ] || [ "$keep" = "0" ]; then
		keep_json=false
		sysupgrade_opts="-n"
	fi
	log "sysupgrade apply keep=${keep_json}"
	# Detach so rpcd can return JSON before reboot kills the session.
	(
		sleep 1
		# shellcheck disable=SC2086
		/sbin/sysupgrade $sysupgrade_opts "$IMG"
	) >/tmp/leandns-sysupgrade.run 2>&1 &
	printf '{"ok":true,"started":true,"keep_settings":%s}\n' "$keep_json"
}

case "${1:-}" in
	status) cmd_status ;;
	prepare) cmd_prepare "${2:-0}" ;;
	abort) cmd_abort ;;
	verify) cmd_verify ;;
	apply) cmd_apply "${2:-true}" ;;
	*)
		echo "usage: $0 status|prepare [bytes]|abort|verify|apply [true|false]" >&2
		exit 1
		;;
esac
