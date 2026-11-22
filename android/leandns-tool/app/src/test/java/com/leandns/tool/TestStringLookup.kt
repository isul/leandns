package com.leandns.tool

/** JVM unit-test stand-in for Android string resources (English defaults). */
object TestStringLookup : StringLookup {
    private val map = mapOf(
        R.string.msg_unknown_error to "Unknown error",
        R.string.msg_set_failed to "SET failed",
        R.string.msg_set_no_reply to
            "No device replied.\n\n· Confirm you are on the same router Wi‑Fi/LAN.\n· If the device just rebooted, wait 1–2 minutes and try again.\n· If the device requires a token, enter it.",
        R.string.msg_set_failed_no_detail to "SET failed (no details).\nReplies: %1\$s",
        R.string.msg_set_success to
            "Applied permanently on the device.\n\nAfter a few seconds open http://%1\$s/leandns/ to manage the device at the new address.\nSettings are kept; they do not auto-revert.",
        R.string.msg_set_hint_pending_change to
            "\n\nAnother network change is still in progress. Wait a moment, then try again.",
        R.string.msg_set_hint_disabled to
            "\n\nAllow UDP IP change on the device web UI System screen.",
        R.string.msg_set_hint_token to
            "\n\nCheck the UDP token shown on the web System screen. If the token is off, leave the field blank.",
        R.string.msg_set_hint_fields to
            "\n\nDouble-check IP, subnet mask, and gateway.",
        R.string.token_udp_disabled to "UDP IP change off",
        R.string.token_not_required to "Not required",
        R.string.token_required to "Required",
        R.string.token_unknown_assume_required to "Unknown (assume required)",
        R.string.token_legacy_daemon to "Legacy daemon · update device",
    )

    override fun get(id: Int, vararg formatArgs: Any): String {
        val template = map[id] ?: error("Missing test string for id=$id")
        if (formatArgs.isEmpty()) return template
        var out = template
        formatArgs.forEachIndexed { index, arg ->
            out = out.replace("%${index + 1}\$s", arg.toString())
            out = out.replace("%${index + 1}\$d", arg.toString())
        }
        return out
    }
}
