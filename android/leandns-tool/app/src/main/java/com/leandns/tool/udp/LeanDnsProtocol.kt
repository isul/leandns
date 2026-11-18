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
            "SET_ERR" -> ProtocolReply.SetErr(
                from = from,
                detail = parts.getOrNull(2).orEmpty(),
                message = extractErrorMessage(parts.getOrNull(2).orEmpty()),
            )
            else -> ProtocolReply.Raw(from, text)
        }
    }

    /** Pull `error` from SET_ERR JSON body, or return the raw detail. */
    fun extractErrorMessage(detail: String): String {
        val trimmed = detail.trim()
        if (trimmed.isEmpty()) return "알 수 없는 오류"
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
    fun formatSetFailure(replies: List<ProtocolReply>): String {
        if (replies.isEmpty()) {
            return """
                장치 응답이 없습니다.

                · 같은 공유기 Wi‑Fi/LAN인지 확인하세요.
                · 장비가 막 재부팅됐다면 1~2분 뒤 다시 시도하세요.
                · 토큰이 필요한 장치면 토큰을 입력하세요.
            """.trimIndent()
        }

        val errors = replies.mapNotNull { reply ->
            when (reply) {
                is ProtocolReply.SetErr -> enrichSetError(reply.message)
                is ProtocolReply.Raw -> enrichSetError(extractErrorMessage(stripSetErrPrefix(reply.text)))
                is ProtocolReply.SetOk -> null
                is ProtocolReply.DiscoverInfo -> null
            }
        }.distinct()

        return if (errors.isEmpty()) {
            "SET 실패 (상세 응답 없음).\n응답: ${replies.joinToString { it.summaryLine() }}"
        } else {
            errors.joinToString("\n\n")
        }
    }

    fun formatSetSuccess(ip: String): String {
        return """
            임시 적용되었습니다.

            수 초 후 http://$ip/leandns/ 로 접속해 시스템 화면에서 120초 안에 LAN 설정을 확정하세요.
            확정하지 않으면 이전 설정으로 복구됩니다.

            확정·복구 전에는 추가 적용이 거부됩니다.
        """.trimIndent()
    }

    private fun stripSetErrPrefix(text: String): String {
        val parts = text.split("|", limit = 3)
        return if (parts.size >= 3 && parts[0] == MAGIC && parts[1] == "SET_ERR") {
            parts[2]
        } else {
            text
        }
    }

    private fun enrichSetError(message: String): String {
        val base = message.trim().ifBlank { "SET 실패" }
        return when {
            base.contains("다른 네트워크 변경") ->
                "$base\n\n웹 UI에서 임시 설정을 확정하거나, 120초 후 자동 복구될 때까지 기다린 뒤 다시 시도하세요."
            base.contains("비활성화") || base.contains("disabled") ->
                "$base\n\n장치 웹 UI 시스템 화면에서 UDP IP 변경을 허용하세요."
            base.contains("unauthorized") || base.contains("토큰") || base.contains("token") ->
                "$base\n\n웹 시스템 화면에 표시된 UDP 토큰을 확인하세요. 토큰이 꺼져 있으면 입력란을 비우세요."
            base.contains("IP 주소") || base.contains("missing fields") || base.contains("bad json") ->
                "$base\n\nIP · 서브넷 마스크 · 게이트웨이를 다시 확인하세요."
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
