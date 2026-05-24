package cool.happyword.wordmagic.ui

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
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.text.style.TextAlign
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
    manifestBusy: Boolean,
    applying: Boolean,
    onSelectEnv: (BackendEnv) -> Unit,
    onRefreshManifest: () -> Unit,
    onSelectPreview: (PreviewTarget) -> Unit,
    onProbe: () -> Unit,
    onBypassSecret: () -> Unit,
    onClear: () -> Unit,
    onBack: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxSize()
            .background(Color.White)
            .verticalScroll(rememberScrollState())
            .topChromeSafeInsets()
            .padding(
                start = PageChromeInsets.bodyHorizontal,
                top = PageChromeInsets.bodyTop,
                end = PageChromeInsets.bodyHorizontal,
                bottom = PageChromeInsets.bodyBottom,
            )
            .testTag("DevMenuScreen"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier.testTag("DevMenuBackButton"),
            )
            Text(
                "Developer Options",
                modifier = Modifier.padding(start = 16.dp),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF303030),
            )
            Spacer(Modifier.weight(1f))
            HarmonyDevMenuButton("Bypass Secret", Modifier.testTag("DevMenuBypassSecretButton"), enabled = !applying, onClick = onBypassSecret)
            Spacer(Modifier.width(10.dp))
            HarmonyDevMenuButton(
                if (manifestBusy) "Refreshing..." else "Refresh Manifest",
                Modifier.testTag("DevMenuRefreshManifestButton"),
                enabled = !manifestBusy && !applying,
                onClick = onRefreshManifest,
            )
        }
        Text(
            "Backend environment (debug builds only)",
            modifier = Modifier.padding(top = 16.dp, bottom = 12.dp),
            fontSize = 14.sp,
            color = Color(0xFF666666),
        )

        val cards = devMenuCards(state, previews)
        cards.chunked(2).forEach { rowCards ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp),
                verticalAlignment = Alignment.Top,
            ) {
                rowCards.forEach { card ->
                    DevMenuCard(
                        card,
                        modifier = Modifier.weight(1f),
                        enabled = !applying,
                        onSelectEnv = onSelectEnv,
                        onSelectPreview = onSelectPreview,
                    )
                }
                if (rowCards.size == 1) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }

        if (previews.isEmpty()) {
            Text(
                if (manifestBusy) "Loading manifest..." else "No manifest available",
                modifier = Modifier.padding(bottom = 16.dp),
                fontSize = 12.sp,
                color = Color(0xFF888888),
            )
        }

        if (probeStatus.isNotBlank() && probeStatus != "尚未探测") {
            Text("Last health probe", fontSize = 12.sp, color = Color(0xFF666666), modifier = Modifier.padding(top = 16.dp, bottom = 4.dp))
            Text(probeStatus, modifier = Modifier.fillMaxWidth().testTag("DevMenuLastProbeStatus"), fontSize = 11.sp, color = Color(0xFF444444))
        }

        Text(
            routingSummary.replaceFirst("${state.env.label}: ", "API base: "),
            modifier = Modifier.padding(top = 16.dp).fillMaxWidth().testTag("DevMenuRoutingDebug"),
            color = Color(0xFF888888),
            fontSize = 11.sp,
        )
    }
}

private data class DevMenuCardUi(
    val id: String,
    val title: String,
    val footer: String,
    val env: BackendEnv,
    val preview: PreviewTarget? = null,
    val highlighted: Boolean = false,
)

private fun devMenuCards(state: BackendRouteState, previews: List<PreviewTarget>): List<DevMenuCardUi> {
    val local = DevMenuCardUi(
        id = "DevMenuLocalCard",
        title = BackendEnv.Local.label,
        footer = BackendEnv.Local.defaultUrl,
        env = BackendEnv.Local,
        highlighted = state.env == BackendEnv.Local,
    )
    val staging = DevMenuCardUi(
        id = "DevMenuStagingCard",
        title = BackendEnv.Staging.label,
        footer = BackendEnv.Staging.defaultUrl,
        env = BackendEnv.Staging,
        highlighted = state.env == BackendEnv.Staging,
    )
    val previewCards = previews.map { preview ->
        DevMenuCardUi(
            id = "DevMenuPreviewCard_${preview.id}",
            title = preview.label,
            footer = preview.footer,
            env = BackendEnv.Preview,
            preview = preview,
            highlighted = state.env == BackendEnv.Preview && state.selectedPreview?.url?.trimEnd('/') == preview.url.trimEnd('/'),
        )
    }
    return listOf(local, staging) + previewCards
}

@Composable
private fun HarmonyDevMenuButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = modifier.height(36.dp),
        enabled = enabled,
        shape = RoundedCornerShape(18.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF0A62F0)),
    ) {
        Text(text, fontSize = 14.sp, color = Color.White)
    }
}

@Composable
private fun DevMenuCard(
    card: DevMenuCardUi,
    modifier: Modifier = Modifier,
    enabled: Boolean,
    onSelectEnv: (BackendEnv) -> Unit,
    onSelectPreview: (PreviewTarget) -> Unit,
) {
    val tagModifier = if (card.preview == null) {
        Modifier.testTag(card.id)
    } else {
        Modifier.testTag("DevMenuPreviewRow_${card.preview.id}")
    }
    Column(
        modifier = modifier
            .then(tagModifier)
            .height(96.dp)
            .background(if (card.highlighted) Color(0xFFCDE8FF) else Color(0xFFF5F5F5), RoundedCornerShape(12.dp))
            .border(1.dp, if (card.highlighted) Color(0xFF457B9D) else Color(0xFFE0E0E0), RoundedCornerShape(12.dp))
            .clickable(enabled = enabled) {
                val preview = card.preview
                if (preview == null) onSelectEnv(card.env) else onSelectPreview(preview)
            }
            .padding(12.dp),
        verticalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            card.title,
            modifier = Modifier.fillMaxWidth(),
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF222222),
            maxLines = 2,
        )
        Text(
            card.footer,
            modifier = Modifier.fillMaxWidth(),
            fontSize = 13.sp,
            color = Color(0xFF555555),
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
        if (card.preview != null) {
            Box(Modifier.size(1.dp).testTag(card.id))
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
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFFFFF6E7))
            .topChromeSafeInsets()
            .padding(
                start = PageChromeInsets.bodyHorizontal,
                top = PageChromeInsets.bodyTop,
                end = PageChromeInsets.bodyHorizontal,
                bottom = PageChromeInsets.bodyBottom,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            HarmonyPageTopBackButton(
                onClick = onCancel,
                modifier = Modifier.testTag("BypassSecretPageBackButton"),
            )
            Spacer(Modifier.weight(1f))
        }
        Text("Bypass Secret", fontSize = 28.sp, fontWeight = FontWeight.Black, modifier = Modifier.testTag("BypassSecretPageTitle"))
        OutlinedTextField(
            value = secret,
            onValueChange = { secret = it },
            label = { Text("Vercel Protection Bypass") },
            modifier = Modifier.padding(top = 18.dp).testTag("BypassSecretPageInput"),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 18.dp)) {
            OutlinedButton(onClick = onClear, modifier = Modifier.testTag("BypassSecretPageClearButton")) { Text("清除") }
            Button(onClick = { onSave(secret) }, modifier = Modifier.testTag("BypassSecretPageSaveButton")) { Text("保存") }
        }
    }
}
