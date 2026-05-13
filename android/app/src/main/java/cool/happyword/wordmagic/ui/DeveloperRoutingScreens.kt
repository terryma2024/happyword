package cool.happyword.wordmagic.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cool.happyword.wordmagic.core.BackendEnv
import cool.happyword.wordmagic.core.BackendRouteState
import cool.happyword.wordmagic.core.PreviewTarget

@Composable
fun DevMenuScreen(
    state: BackendRouteState,
    previews: List<PreviewTarget>,
    routingSummary: String,
    probeStatus: String,
    onSelectEnv: (BackendEnv) -> Unit,
    onRefreshManifest: () -> Unit,
    onSelectPreview: (PreviewTarget) -> Unit,
    onDebugSessionChange: (String) -> Unit,
    onProbe: () -> Unit,
    onBypassSecret: () -> Unit,
    onClear: () -> Unit,
    onBack: () -> Unit,
) {
    Column(Modifier.fillMaxSize().background(Color.White).padding(24.dp).testTag("DevMenuScreen")) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("Developer", fontSize = 28.sp, fontWeight = FontWeight.Black)
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = onBack) { Text("返回") }
        }
        Text(routingSummary, modifier = Modifier.padding(top = 12.dp).testTag("DevMenuRoutingDebug"), color = Color(0xFF6A5843))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 12.dp)) {
            BackendEnv.entries.filterNot { it == BackendEnv.Preview }.forEach { env ->
                OutlinedButton(onClick = { onSelectEnv(env) }) { Text(env.label) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 12.dp)) {
            Button(onClick = onRefreshManifest, modifier = Modifier.testTag("DevMenuRefreshManifestButton"), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050))) { Text("刷新 Preview") }
            OutlinedButton(onClick = onProbe, modifier = Modifier.testTag("DevMenuHealthProbeButton")) { Text("探测") }
            OutlinedButton(onClick = onBypassSecret, modifier = Modifier.testTag("DevMenuBypassSecretButton")) { Text("Bypass") }
            OutlinedButton(onClick = onClear, modifier = Modifier.testTag("DevMenuClearOverrideButton")) { Text("清除") }
        }
        OutlinedTextField(
            value = state.debugSessionId,
            onValueChange = onDebugSessionChange,
            label = { Text("Debug session") },
            modifier = Modifier.padding(top = 12.dp).fillMaxWidth().testTag("DevMenuDebugSessionInput"),
            singleLine = true,
        )
        Text(probeStatus, modifier = Modifier.padding(top = 10.dp).testTag("DevMenuLastProbeStatus"))
        previews.forEach { preview ->
            OutlinedButton(
                onClick = { onSelectPreview(preview) },
                modifier = Modifier.padding(top = 8.dp).testTag("DevMenuPreviewRow_${preview.id}"),
            ) {
                Text("${preview.label} ${if (state.selectedPreview?.id == preview.id) "✓" else ""}")
            }
        }
    }
}

@Composable
fun BypassSecretScreen(
    initialSecret: String,
    onSave: (String) -> Unit,
    onClear: () -> Unit,
    onCancel: () -> Unit,
) {
    var secret by remember(initialSecret) { mutableStateOf(initialSecret) }
    Column(Modifier.fillMaxSize().background(Color(0xFFFFF6E7)).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Bypass Secret", fontSize = 28.sp, fontWeight = FontWeight.Black, modifier = Modifier.testTag("BypassSecretPageTitle"))
        OutlinedTextField(
            value = secret,
            onValueChange = { secret = it },
            label = { Text("Vercel Protection Bypass") },
            modifier = Modifier.padding(top = 18.dp).testTag("BypassSecretPageInput"),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 18.dp)) {
            OutlinedButton(onClick = onCancel, modifier = Modifier.testTag("BypassSecretPageCancelButton")) { Text("取消") }
            OutlinedButton(onClick = onClear, modifier = Modifier.testTag("BypassSecretPageClearButton")) { Text("清除") }
            Button(onClick = { onSave(secret) }, modifier = Modifier.testTag("BypassSecretPageSaveButton")) { Text("保存") }
        }
    }
}
