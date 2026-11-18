package com.leandns.tool

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.leandns.tool.udp.LeanDnsProtocol
import com.leandns.tool.udp.LeanDnsUdpClient
import com.leandns.tool.udp.ProtocolReply
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class ResultDialog(
    val title: String,
    val message: String,
    val isError: Boolean,
)

data class ToolUiState(
    val busy: Boolean = false,
    val status: String = "같은 Wi‑Fi에 연결한 뒤 장치를 검색하세요.",
    val statusIsError: Boolean = false,
    val devices: List<ProtocolReply.DiscoverInfo> = emptyList(),
    val rawReplies: List<String> = emptyList(),
    val token: String = "",
    val ip: String = "",
    val netmask: String = "255.255.255.0",
    val gateway: String = "",
    val lastSetOk: Boolean = false,
    val resultDialog: ResultDialog? = null,
)

class ToolViewModel(app: Application) : AndroidViewModel(app) {
    private val client = LeanDnsUdpClient(app.applicationContext)
    private val _state = MutableStateFlow(ToolUiState())
    val state: StateFlow<ToolUiState> = _state.asStateFlow()

    fun onTokenChange(v: String) = _state.update { it.copy(token = v) }
    fun onIpChange(v: String) = _state.update { it.copy(ip = v) }
    fun onNetmaskChange(v: String) = _state.update { it.copy(netmask = v) }
    fun onGatewayChange(v: String) = _state.update { it.copy(gateway = v) }

    fun dismissResultDialog() = _state.update { it.copy(resultDialog = null) }

    fun selectDevice(info: ProtocolReply.DiscoverInfo) {
        _state.update {
            it.copy(
                ip = info.ipAddr,
                netmask = info.netmask.ifBlank { "255.255.255.0" },
                gateway = info.gateway,
                status = "${info.name.ifBlank { "LeanDNS" }} 선택됨 · ${info.uiUrl}",
                statusIsError = false,
                lastSetOk = false,
            )
        }
    }

    fun discover() {
        if (_state.value.busy) return
        viewModelScope.launch {
            _state.update {
                it.copy(
                    busy = true,
                    status = "UDP/${LeanDnsProtocol.PORT} DISCOVER 브로드캐스트 중…",
                    statusIsError = false,
                    lastSetOk = false,
                    resultDialog = null,
                )
            }
            val result = runCatching {
                withContext(Dispatchers.IO) { client.discover() }
            }
            result.fold(
                onSuccess = { replies ->
                    val devices = replies.filterIsInstance<ProtocolReply.DiscoverInfo>()
                    val raw = replies.map { it.summaryLine() }
                    if (devices.isEmpty()) {
                        val message = if (raw.isEmpty()) {
                            """
                                장치 응답이 없습니다.

                                · 같은 공유기 Wi‑Fi/LAN인지 확인하세요.
                                · 장비가 막 재부팅됐다면 discover 서비스가 뜰 때까지 1~2분 뒤 다시 시도하세요.
                            """.trimIndent()
                        } else {
                            "장치를 해석하지 못했습니다.\n\n${raw.joinToString("\n")}"
                        }
                        _state.update {
                            it.copy(
                                busy = false,
                                devices = emptyList(),
                                rawReplies = raw,
                                status = "장치 응답 없음",
                                statusIsError = true,
                                resultDialog = ResultDialog(
                                    title = "검색 실패",
                                    message = message,
                                    isError = true,
                                ),
                            )
                        }
                    } else {
                        _state.update {
                            it.copy(
                                busy = false,
                                devices = devices,
                                rawReplies = raw,
                                status = "발견 ${devices.size}대",
                                statusIsError = false,
                            )
                        }
                        devices.firstOrNull()?.let { selectDevice(it) }
                    }
                },
                onFailure = { e ->
                    val message = e.message ?: "검색 실패"
                    _state.update {
                        it.copy(
                            busy = false,
                            status = message,
                            statusIsError = true,
                            resultDialog = ResultDialog(
                                title = "검색 실패",
                                message = message,
                                isError = true,
                            ),
                        )
                    }
                },
            )
        }
    }

    fun applySet() {
        if (_state.value.busy) return
        val s = _state.value
        if (s.ip.isBlank() || s.gateway.isBlank()) {
            _state.update {
                it.copy(
                    status = "IP와 게이트웨이를 입력하세요.",
                    statusIsError = true,
                    resultDialog = ResultDialog(
                        title = "입력 확인",
                        message = "IP와 게이트웨이를 입력하세요.",
                        isError = true,
                    ),
                )
            }
            return
        }
        viewModelScope.launch {
            val ip = s.ip.trim()
            val netmask = s.netmask.trim()
            val gateway = s.gateway.trim()
            _state.update {
                it.copy(
                    busy = true,
                    status = "SET → $ip / $netmask gw $gateway",
                    statusIsError = false,
                    lastSetOk = false,
                    resultDialog = null,
                )
            }
            val result = runCatching {
                withContext(Dispatchers.IO) {
                    client.set(s.token.trim(), ip, netmask, gateway)
                }
            }
            result.fold(
                onSuccess = { replies ->
                    val ok = replies.filterIsInstance<ProtocolReply.SetOk>()
                    val raw = replies.map { it.summaryLine() }
                    if (ok.isEmpty()) {
                        val detail = LeanDnsProtocol.formatSetFailure(replies)
                        _state.update {
                            it.copy(
                                busy = false,
                                rawReplies = raw,
                                status = "SET 실패",
                                statusIsError = true,
                                lastSetOk = false,
                                resultDialog = ResultDialog(
                                    title = "SET 실패",
                                    message = detail,
                                    isError = true,
                                ),
                            )
                        }
                    } else {
                        val message = LeanDnsProtocol.formatSetSuccess(ip)
                        _state.update {
                            it.copy(
                                busy = false,
                                rawReplies = raw,
                                status = "임시 적용됨 · 웹에서 120초 안 확정",
                                statusIsError = false,
                                lastSetOk = true,
                                resultDialog = ResultDialog(
                                    title = "적용 완료",
                                    message = message,
                                    isError = false,
                                ),
                            )
                        }
                    }
                },
                onFailure = { e ->
                    val message = e.message ?: "SET 실패"
                    _state.update {
                        it.copy(
                            busy = false,
                            status = message,
                            statusIsError = true,
                            lastSetOk = false,
                            resultDialog = ResultDialog(
                                title = "SET 실패",
                                message = message,
                                isError = true,
                            ),
                        )
                    }
                },
            )
        }
    }
}
