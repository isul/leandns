package com.leandns.tool.udp

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

    fun parseReply(from: String, text: String): ProtocolReply {
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
            else -> ProtocolReply.Raw(from, text)
        }
    }
}

sealed class ProtocolReply {
    abstract val from: String

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
        val tokenLabel: String
            get() = when (setEnabled) {
                false -> "UDP IP 변경 끔"
                true -> when (tokenRequired) {
                    false -> "불필요"
                    true -> "필요"
                    null -> "알 수 없음 (필요 가정)"
                }
                // Old discoverd omitted set_enabled and always sent token_required=true.
                null -> "구버전 데몬 · 장치 업데이트 필요"
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

    data class Raw(
        override val from: String,
        val text: String,
    ) : ProtocolReply()
}
