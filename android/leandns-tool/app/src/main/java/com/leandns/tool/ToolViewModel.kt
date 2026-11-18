package com.leandns.tool

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.leandns.tool.udp.LeanDnsUdpClient
import com.leandns.tool.udp.ProtocolReply
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
)

class ToolViewModel(app: Application) : AndroidViewModel(app) {
    private val client = LeanDnsUdpClient(app.applicationContext)
    private val _state = MutableStateFlow(ToolUiState())
    val state: StateFlow<ToolUiState> = _state.asStateFlow()

    fun onTokenChange(v: String) = _state.update { it.copy(token = v) }
    fun onIpChange(v: String) = _state.update { it.copy(ip = v) }
    fun onNetmaskChange(v: String) = _state.update { it.copy(netmask = v) }
    fun onGatewayChange(v: String) = _state.update { it.copy(gateway = v) }

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
                    status = "UDP/${com.leandns.tool.udp.LeanDnsProtocol.PORT} DISCOVER 브로드캐스트 중…",
                    statusIsError = false,
                    lastSetOk = false,
                )
            }
            val result = runCatching {
                withContext(Dispatchers.IO) { client.discover() }
            }
            result.fold(
                onSuccess = { replies ->
                    val devices = replies.filterIsInstance<ProtocolReply.DiscoverInfo>()
                    val raw = replies.filterIsInstance<ProtocolReply.Raw>().map { "${it.from}: ${it.text}" }
                    if (devices.isEmpty() && raw.isEmpty()) {
                        _state.update {
                            it.copy(
                                busy = false,
                                devices = emptyList(),
                                rawReplies = emptyList(),
                                status = "장치 응답 없음. 같은 공유기 Wi‑Fi/LAN인지 확인하세요.",
                                statusIsError = true,
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
                    _state.update {
                        it.copy(
                            busy = false,
                            status = e.message ?: "검색 실패",
                            statusIsError = true,
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
                it.copy(status = "IP와 게이트웨이를 입력하세요.", statusIsError = true)
            }
            return
        }
        viewModelScope.launch {
            _state.update {
                it.copy(
                    busy = true,
                    status = "SET → ${s.ip} / ${s.netmask} gw ${s.gateway}",
                    statusIsError = false,
                    lastSetOk = false,
                )
            }
            val result = runCatching {
                withContext(Dispatchers.IO) {
                    client.set(s.token.trim(), s.ip.trim(), s.netmask.trim(), s.gateway.trim())
                }
            }
            result.fold(
                onSuccess = { replies ->
                    val ok = replies.filterIsInstance<ProtocolReply.SetOk>()
                    val raw = replies.map {
                        when (it) {
                            is ProtocolReply.SetOk -> "OK ${it.from}: ${it.detail}"
                            is ProtocolReply.Raw -> "${it.from}: ${it.text}"
                            is ProtocolReply.DiscoverInfo -> "${it.from}: DISCOVER_OK"
                        }
                    }
                    if (ok.isEmpty()) {
                        _state.update {
                            it.copy(
                                busy = false,
                                rawReplies = raw,
                                status = if (replies.isEmpty()) {
                                    "응답 없음 (토큰·방화벽·L2 연결 확인)"
                                } else {
                                    "SET 실패"
                                },
                                statusIsError = true,
                                lastSetOk = false,
                            )
                        }
                    } else {
                        _state.update {
                            it.copy(
                                busy = false,
                                rawReplies = raw,
                                status = "적용됨. 수 초 후 http://${s.ip.trim()}/leandns/ 로 접속하세요.",
                                statusIsError = false,
                                lastSetOk = true,
                            )
                        }
                    }
                },
                onFailure = { e ->
                    _state.update {
                        it.copy(
                            busy = false,
                            status = e.message ?: "SET 실패",
                            statusIsError = true,
                            lastSetOk = false,
                        )
                    }
                },
            )
        }
    }
}
