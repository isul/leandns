package com.leandns.tool.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Radar
import androidx.compose.material.icons.filled.Save
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.leandns.tool.ResultDialog
import com.leandns.tool.ToolUiState
import com.leandns.tool.ToolViewModel
import com.leandns.tool.udp.ProtocolReply

@Composable
fun ToolScreen(
    viewModel: ToolViewModel,
    modifier: Modifier = Modifier,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val scroll = rememberScrollState()

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        MaterialTheme.colorScheme.surfaceVariant,
                        MaterialTheme.colorScheme.background,
                        MaterialTheme.colorScheme.background,
                    ),
                ),
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scroll)
                .padding(horizontal = 20.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            BrandHeader()

            // Progress / short context only — final results use ResultAlertDialog.
            StatusBanner(state)

            DiscoverSection(
                busy = state.busy,
                devices = state.devices,
                onDiscover = viewModel::discover,
                onSelect = viewModel::selectDevice,
                onOpenUi = { url ->
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                },
            )

            SetSection(
                state = state,
                onToken = viewModel::onTokenChange,
                onIp = viewModel::onIpChange,
                onNetmask = viewModel::onNetmaskChange,
                onGateway = viewModel::onGatewayChange,
                onApply = viewModel::applySet,
                onOpenUi = {
                    val ip = state.ip.trim()
                    if (ip.isNotEmpty()) {
                        context.startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse("http://$ip/leandns/")),
                        )
                    }
                },
            )

            if (state.rawReplies.isNotEmpty()) {
                RawLog(state.rawReplies)
            }

            Text(
                text = "프로토콜 LEANDNS1 · UDP 37421 · PC leandns-tool과 동일",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    state.resultDialog?.let { dialog ->
        ResultAlertDialog(
            dialog = dialog,
            onDismiss = viewModel::dismissResultDialog,
            onOpenUi = if (!dialog.isError && state.ip.isNotBlank()) {
                {
                    val ip = state.ip.trim()
                    viewModel.dismissResultDialog()
                    context.startActivity(
                        Intent(Intent.ACTION_VIEW, Uri.parse("http://$ip/leandns/")),
                    )
                }
            } else {
                null
            },
        )
    }
}

@Composable
private fun ResultAlertDialog(
    dialog: ResultDialog,
    onDismiss: () -> Unit,
    onOpenUi: (() -> Unit)?,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = dialog.title,
                color = if (dialog.isError) {
                    MaterialTheme.colorScheme.error
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
            )
        },
        text = {
            Text(
                text = dialog.message,
                style = MaterialTheme.typography.bodyMedium,
            )
        },
        confirmButton = {
            if (onOpenUi != null) {
                TextButton(onClick = onOpenUi) {
                    Text("웹 UI 열기")
                }
            } else {
                TextButton(onClick = onDismiss) {
                    Text("확인")
                }
            }
        },
        dismissButton = if (onOpenUi != null) {
            {
                TextButton(onClick = onDismiss) {
                    Text("닫기")
                }
            }
        } else {
            null
        },
    )
}

@Composable
private fun BrandHeader() {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            text = "LeanDNS",
            style = MaterialTheme.typography.displayLarge,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = "LAN 발견 · 관리 IP 설정",
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Text(
            text = "서브넷이 달라도 같은 공유기 Wi‑Fi면 장치를 찾아 IP를 바꿀 수 있습니다.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun StatusBanner(state: ToolUiState) {
    val bg = when {
        state.statusIsError -> MaterialTheme.colorScheme.error.copy(alpha = 0.12f)
        state.lastSetOk -> MaterialTheme.colorScheme.primary.copy(alpha = 0.14f)
        else -> MaterialTheme.colorScheme.surface.copy(alpha = 0.7f)
    }
    val fg = when {
        state.statusIsError -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurface
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(bg)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.busy) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.primary,
            )
        }
        Text(text = state.status, color = fg, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun DiscoverSection(
    busy: Boolean,
    devices: List<ProtocolReply.DiscoverInfo>,
    onDiscover: () -> Unit,
    onSelect: (ProtocolReply.DiscoverInfo) -> Unit,
    onOpenUi: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("장치 검색", style = MaterialTheme.typography.titleLarge)
            Button(onClick = onDiscover, enabled = !busy) {
                Icon(Icons.Default.Radar, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text("검색")
            }
        }

        AnimatedVisibility(
            visible = devices.isNotEmpty(),
            enter = fadeIn() + slideInVertically { it / 3 },
            exit = fadeOut(),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                devices.forEach { device ->
                    DeviceRow(device, onSelect, onOpenUi)
                }
            }
        }
    }
}

@Composable
private fun DeviceRow(
    device: ProtocolReply.DiscoverInfo,
    onSelect: (ProtocolReply.DiscoverInfo) -> Unit,
    onOpenUi: (String) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface)
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.6f), RoundedCornerShape(12.dp))
            .clickable { onSelect(device) }
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = device.name.ifBlank { "LeanDNS" },
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.primary,
        )
        Fact("IP", device.ipAddr)
        Fact("마스크", device.netmask)
        Fact("GW", device.gateway)
        Fact("MAC", device.mac)
        Fact("버전", device.version)
        Fact(
            "SET",
            when (device.setEnabled) {
                true -> "허용"
                false -> "끔"
                null -> "—"
            },
        )
        Fact("토큰", device.tokenLabel)
        Fact("응답", device.from)
        OutlinedButton(onClick = { onOpenUi(device.uiUrl) }) {
            Icon(Icons.Default.OpenInBrowser, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.size(8.dp))
            Text("웹 UI 열기")
        }
    }
}

@Composable
private fun Fact(label: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(56.dp),
        )
        Text(
            text = value.ifBlank { "—" },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun SetSection(
    state: ToolUiState,
    onToken: (String) -> Unit,
    onIp: (String) -> Unit,
    onNetmask: (String) -> Unit,
    onGateway: (String) -> Unit,
    onApply: () -> Unit,
    onOpenUi: () -> Unit,
) {
    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedBorderColor = MaterialTheme.colorScheme.primary,
        unfocusedBorderColor = MaterialTheme.colorScheme.outline,
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.92f))
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.55f), RoundedCornerShape(12.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("LAN 설정 (UDP SET)", style = MaterialTheme.typography.titleLarge)
        Text(
            text = "웹 시스템 화면의 「UDP IP 변경에 토큰 필요」가 꺼져 있으면 토큰을 비워 두세요.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = state.token,
            onValueChange = onToken,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("토큰 (선택)") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            colors = fieldColors,
        )
        OutlinedTextField(
            value = state.ip,
            onValueChange = onIp,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("새 LAN IP") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            colors = fieldColors,
        )
        OutlinedTextField(
            value = state.netmask,
            onValueChange = onNetmask,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("서브넷 마스크") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            colors = fieldColors,
        )
        OutlinedTextField(
            value = state.gateway,
            onValueChange = onGateway,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("게이트웨이") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            colors = fieldColors,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(onClick = onApply, enabled = !state.busy) {
                Icon(Icons.Default.Save, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text("적용")
            }
            OutlinedButton(onClick = onOpenUi, enabled = state.ip.isNotBlank()) {
                Icon(Icons.Default.OpenInBrowser, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text("UI")
            }
        }
    }
}

@Composable
private fun RawLog(lines: List<String>) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.45f))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text("응답 로그", style = MaterialTheme.typography.titleMedium)
        lines.forEach { line ->
            Text(line, style = MaterialTheme.typography.labelLarge)
        }
        Spacer(Modifier.height(2.dp))
    }
}
