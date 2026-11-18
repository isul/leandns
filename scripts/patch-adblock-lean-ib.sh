#!/usr/bin/env bash
# Soften adblock-lean's host-/bin/sh process-substitution self-check for Image Builder.
# On the build host /bin/sh is often dash (no >()), so staging prints a scary Error and
# aborts early — even though device BusyBox ash supports it and DISABLED_SERVICES only
# meant to skip enable. Skip the check when IPKG_INSTROOT is set (opkg/IB rootfs staging).
set -euo pipefail

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  echo "usage: $0 <path-to-etc/init.d/adblock-lean>" >&2
  exit 2
fi

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
marker = "# LeanDNS: skip process-substitution self-check under IPKG_INSTROOT"
if marker in text:
    print(f"OK: already patched {path}")
    raise SystemExit(0)

old = """# test process substitution support
printf '%s\\n%s\\n' \"#!/bin/sh\" \"printf %s >(:)\" > /tmp/abl-test
if ! /bin/sh /tmp/abl-test 1>/dev/null 2>/dev/null
then
	rm -f /tmp/abl-test
	reg_failure \"This shell does not support process substitution. To use adblock-lean, please update OpenWrt to 22.03 or later version.\"
	graceful_exit 1
fi
rm -f /tmp/abl-test"""

new = """# test process substitution support
# LeanDNS: skip process-substitution self-check under IPKG_INSTROOT
# (Image Builder / opkg staging uses host /bin/sh, often dash without >().
#  Device ash supports it; keep the real check for on-device runs.)
if [ -z \"${IPKG_INSTROOT}\" ]
then
	printf '%s\\n%s\\n' \"#!/bin/sh\" \"printf %s >(:)\" > /tmp/abl-test
	if ! /bin/sh /tmp/abl-test 1>/dev/null 2>/dev/null
	then
		rm -f /tmp/abl-test
		reg_failure \"This shell does not support process substitution. To use adblock-lean, please update OpenWrt to 22.03 or later version.\"
		graceful_exit 1
	fi
	rm -f /tmp/abl-test
fi"""

if old not in text:
    # tolerate already-indented or slightly different quoting from upstream
    import re
    pat = re.compile(
        r"# test process substitution support\n"
        r"printf '%s\\n%s\\n' \"#!/bin/sh\" \"printf %s >\(:\)\" > /tmp/abl-test\n"
        r"if ! /bin/sh /tmp/abl-test 1>/dev/null 2>/dev/null\n"
        r"then\n"
        r"\trm -f /tmp/abl-test\n"
        r"\treg_failure \"This shell does not support process substitution\. To use adblock-lean, please update OpenWrt to 22\.03 or later version\.\"\n"
        r"\tgraceful_exit 1\n"
        r"fi\n"
        r"rm -f /tmp/abl-test",
        re.M,
    )
    text2, n = pat.subn(new, text, count=1)
    if n != 1:
        raise SystemExit(f"ERROR: process-substitution block not found in {path}")
    text = text2
else:
    text = text.replace(old, new, 1)

path.write_text(text)
print(f"OK: patched {path}")
PY
