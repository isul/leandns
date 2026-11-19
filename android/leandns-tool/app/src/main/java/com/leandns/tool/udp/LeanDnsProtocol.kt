package com.leandns.tool.udp

import com.leandns.tool.R
import com.leandns.tool.StringLookup
import org.json.JSONObject

/** Same wire protocol as cmd/leandns-tool (LEANDNS1 / UDP 37421). */
object LeanDnsProtocol {
    const val PORT = 37421
    const val MAGIC = "LEANDNS1"

    fun discoverPayload(): String = "$MAGIC|DISCOVER"

    fun setPayload(token: String, ip: String, netmask: String, gateway: String): String {
        val body = JSONObject()
            .put("token", token)
            .put("ipaddr", ip)
            .put("netmask", netmask)
            .put("gateway", gateway)
        return "$MAGIC|SET|$body"
    }

    fun parseReply(from: String, text: String, strings: StringLookup): ProtocolReply {
        val parts = text.split("|", limit = 3)
        if (parts.size < 2 || parts[0] != MAGIC) {
            return ProtocolReply.Raw(from, text)
        }
        return when (parts[1]) {
            "DISCOVER_OK" -> {
                val json = parts.getOrNull(2).orEmpty()
                runCatching { ProtocolReply.DiscoverInfo.fromJson(from, json) }
                    .getOrElse { ProtocolReply.Raw(from, text) }
            }
            "SET_OK" -> ProtocolReply.SetOk(from, parts.getOrNull(2).orEmpty())
            "SET_ERR" -> ProtocolReply.SetErr(
                from = from,
                detail = parts.getOrNull(2).orEmpty(),
                message = extractErrorMessage(parts.getOrNull(2).orEmpty(), strings),
            )
            else -> ProtocolReply.Raw(from, text)
        }
    }

    /** Pull `error` from SET_ERR JSON body, or return the raw detail. */
    fun extractErrorMessage(detail: String, strings: StringLookup): String {
        val trimmed = detail.trim()
        if (trimmed.isEmpty()) return strings.get(R.string.msg_unknown_error)
        val fromJson = runCatching {
            val o = JSONObject(trimmed)
            when {
                o.has("error") && !o.isNull("error") -> o.getString("error").trim()
                else -> ""
            }
        }.getOrDefault("")
        return fromJson.ifBlank { trimmed }
    }

    /** User-facing SET failure text (detail + short guidance). */
    fun formatSetFailure(replies: List<ProtocolReply>, strings: StringLookup): String {
        if (replies.isEmpty()) {
            return strings.get(R.string.msg_set_no_reply)
        }

        val errors = replies.mapNotNull { reply ->
            when (reply) {
                is ProtocolReply.SetErr -> enrichSetError(reply.message, strings)
                is ProtocolReply.Raw -> enrichSetError(
                    extractErrorMessage(stripSetErrPrefix(reply.text), strings),
                    strings,
                )
                is ProtocolReply.SetOk -> null
                is ProtocolReply.DiscoverInfo -> null
            }
        }.distinct()

        return if (errors.isEmpty()) {
            strings.get(
                R.string.msg_set_failed_no_detail,
                replies.joinToString { it.summaryLine() },
            )
        } else {
            errors.joinToString("\n\n")
        }
    }

    fun formatSetSuccess(ip: String, strings: StringLookup): String =
        strings.get(R.string.msg_set_success, ip)

    private fun stripSetErrPrefix(text: String): String {
        val parts = text.split("|", limit = 3)
        return if (parts.size >= 3 && parts[0] == MAGIC && parts[1] == "SET_ERR") {
            parts[2]
        } else {
            text
        }
    }

    private fun enrichSetError(message: String, strings: StringLookup): String {
        val base = message.trim().ifBlank { strings.get(R.string.msg_set_failed) }
        // Match firmware SET_ERR text (device may reply in Korean or English).
        return when {
            base.contains("다른 네트워크 변경") ->
                base + strings.get(R.string.msg_set_hint_pending_change)
            base.contains("비활성화") ||
                base.contains("disabled", ignoreCase = true) ->
                base + strings.get(R.string.msg_set_hint_disabled)
            base.contains("unauthorized", ignoreCase = true) ||
                base.contains("토큰") ||
                base.contains("token", ignoreCase = true) ->
                base + strings.get(R.string.msg_set_hint_token)
            base.contains("IP 주소") ||
                base.contains("missing fields", ignoreCase = true) ||
                base.contains("bad json", ignoreCase = true) ->
                base + strings.get(R.string.msg_set_hint_fields)
            else -> base
        }
    }
}

sealed class ProtocolReply {
    abstract val from: String

    fun summaryLine(): String = when (this) {
        is DiscoverInfo -> "$from: DISCOVER_OK"
        is SetOk -> "OK $from: $detail"
        is SetErr -> "$from: SET_ERR · $message"
        is Raw -> "$from: $text"
    }

    data class DiscoverInfo(
        override val from: String,
        val name: String,
        val version: String,
        val ipAddr: String,
        val netmask: String,
        val gateway: String,
        val mac: String,
        val tokenRequired: Boolean?,
        val setEnabled: Boolean?,
    ) : ProtocolReply() {
        val uiUrl: String get() = "http://$ipAddr/leandns/"

        /** Combined status for the device card (SET gate + token policy). */
        fun tokenLabel(strings: StringLookup): String = when (setEnabled) {
            false -> strings.get(R.string.token_udp_disabled)
            true -> when (tokenRequired) {
                false -> strings.get(R.string.token_not_required)
                true -> strings.get(R.string.token_required)
                null -> strings.get(R.string.token_unknown_assume_required)
            }
            // Old discoverd omitted set_enabled and always sent token_required=true.
            null -> strings.get(R.string.token_legacy_daemon)
        }

        companion object {
            fun fromJson(from: String, raw: String): DiscoverInfo {
                val o = JSONObject(raw)
                val tokenRequired = if (o.has("token_required") && !o.isNull("token_required")) {
                    o.getBoolean("token_required")
                } else {
                    null
                }
                val setEnabled = if (o.has("set_enabled") && !o.isNull("set_enabled")) {
                    o.getBoolean("set_enabled")
                } else {
                    null
                }
                return DiscoverInfo(
                    from = from,
                    name = o.optString("name"),
                    version = o.optString("version"),
                    ipAddr = o.optString("ipaddr"),
                    netmask = o.optString("netmask"),
                    gateway = o.optString("gateway"),
                    mac = o.optString("mac"),
                    tokenRequired = tokenRequired,
                    setEnabled = setEnabled,
                )
            }
        }
    }

    data class SetOk(
        override val from: String,
        val detail: String,
    ) : ProtocolReply()

    data class SetErr(
        override val from: String,
        val detail: String,
        val message: String,
    ) : ProtocolReply()

    data class Raw(
        override val from: String,
        val text: String,
    ) : ProtocolReply()
}
