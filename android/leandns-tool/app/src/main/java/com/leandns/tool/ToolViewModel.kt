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
    val status: String = "",
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
    private val strings = app.asStringLookup()
    private val client = LeanDnsUdpClient(app.applicationContext)
    private val _state = MutableStateFlow(ToolUiState(status = strings.get(R.string.status_idle)))
    val state: StateFlow<ToolUiState> = _state.asStateFlow()

    fun onTokenChange(v: String) = _state.update { it.copy(token = v) }
    fun onIpChange(v: String) = _state.update { it.copy(ip = v) }
    fun onNetmaskChange(v: String) = _state.update { it.copy(netmask = v) }
    fun onGatewayChange(v: String) = _state.update { it.copy(gateway = v) }

    fun dismissResultDialog() = _state.update { it.copy(resultDialog = null) }

    fun selectDevice(info: ProtocolReply.DiscoverInfo) {
        val name = info.name.ifBlank { strings.get(R.string.default_device_name) }
        _state.update {
            it.copy(
                ip = info.ipAddr,
                netmask = info.netmask.ifBlank { "255.255.255.0" },
                gateway = info.gateway,
                status = strings.get(R.string.status_selected, name, info.uiUrl),
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
                    status = strings.get(R.string.status_discovering, LeanDnsProtocol.PORT),
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
                            strings.get(R.string.msg_discover_no_reply)
                        } else {
                            strings.get(R.string.msg_could_not_parse_devices, raw.joinToString("\n"))
                        }
                        _state.update {
                            it.copy(
                                busy = false,
                                devices = emptyList(),
                                rawReplies = raw,
                                status = strings.get(R.string.status_no_device_reply),
                                statusIsError = true,
                                resultDialog = ResultDialog(
                                    title = strings.get(R.string.dialog_discover_failed_title),
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
                                status = strings.get(R.string.status_found_count, devices.size),
                                statusIsError = false,
                            )
                        }
                        devices.firstOrNull()?.let { selectDevice(it) }
                    }
                },
                onFailure = { e ->
                    val message = e.message ?: strings.get(R.string.dialog_discover_failed_title)
                    _state.update {
                        it.copy(
                            busy = false,
                            status = message,
                            statusIsError = true,
                            resultDialog = ResultDialog(
                                title = strings.get(R.string.dialog_discover_failed_title),
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
            val message = strings.get(R.string.msg_ip_gateway_required)
            _state.update {
                it.copy(
                    status = message,
                    statusIsError = true,
                    resultDialog = ResultDialog(
                        title = strings.get(R.string.dialog_input_required_title),
                        message = message,
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
                    status = strings.get(R.string.status_set_in_progress, ip, netmask, gateway),
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
                        val detail = LeanDnsProtocol.formatSetFailure(replies, strings)
                        _state.update {
                            it.copy(
                                busy = false,
                                rawReplies = raw,
                                status = strings.get(R.string.status_set_failed),
                                statusIsError = true,
                                lastSetOk = false,
                                resultDialog = ResultDialog(
                                    title = strings.get(R.string.dialog_set_failed_title),
                                    message = detail,
                                    isError = true,
                                ),
                            )
                        }
                    } else {
                        val message = LeanDnsProtocol.formatSetSuccess(ip, strings)
                        _state.update {
                            it.copy(
                                busy = false,
                                rawReplies = raw,
                                status = strings.get(R.string.status_set_pending_confirm),
                                statusIsError = false,
                                lastSetOk = true,
                                resultDialog = ResultDialog(
                                    title = strings.get(R.string.dialog_set_success_title),
                                    message = message,
                                    isError = false,
                                ),
                            )
                        }
                    }
                },
                onFailure = { e ->
                    val message = e.message ?: strings.get(R.string.msg_set_failed)
                    _state.update {
                        it.copy(
                            busy = false,
                            status = message,
                            statusIsError = true,
                            lastSetOk = false,
                            resultDialog = ResultDialog(
                                title = strings.get(R.string.dialog_set_failed_title),
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
