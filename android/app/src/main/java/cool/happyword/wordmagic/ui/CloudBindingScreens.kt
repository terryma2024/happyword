package cool.happyword.wordmagic.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import cool.happyword.wordmagic.core.CloudCredentials
import cool.happyword.wordmagic.core.CompliancePolicy
import cool.happyword.wordmagic.core.SystemBrowser
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val childAvatarEmojiBackupPool = listOf("🦄", "🐻", "🐰", "🦁", "🐼", "🦊", "🐶", "🐱", "🐨", "🐧")
internal const val ChildAvatarEmojiWrapEnabled = true

internal fun childAvatarEmojiChoices(initial: String): List<String> {
    val first = initial.trim().ifBlank { "🦄" }
    return (listOf(first) + childAvatarEmojiBackupPool).distinct().take(10)
}

@Composable
private fun ScanBindingParentLoginLink(onOpenParentLogin: () -> Unit, testTag: String) {
    TextButton(
        onClick = onOpenParentLogin,
        modifier = Modifier
            .padding(top = 8.dp)
            .testTag(testTag),
    ) {
        Text("创建或登录 家长账号", color = Color(0xFF2563EB), fontSize = 14.sp)
    }
}

@Composable
private fun ScanBindingComplianceLinks() {
    val context = LocalContext.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            "绑定或登录前请阅读",
            color = Color(0xFF475569),
            fontSize = 12.sp,
            modifier = Modifier.testTag("ScanBindingCompliancePrompt"),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(
                onClick = { SystemBrowser.openUrl(context, CompliancePolicy.TERMS_OF_SERVICE_URL) },
                modifier = Modifier.testTag("ScanBindingTermsButton"),
            ) {
                Text("用户协议", color = Color(0xFF2563EB), fontSize = 13.sp)
            }
            TextButton(
                onClick = { SystemBrowser.openUrl(context, CompliancePolicy.PRIVACY_POLICY_URL) },
                modifier = Modifier.testTag("ScanBindingPrivacyButton"),
            ) {
                Text("隐私政策", color = Color(0xFF2563EB), fontSize = 13.sp)
            }
        }
    }
}

@Composable
fun ScanBindingScreen(
    busy: Boolean,
    failureReason: String,
    boundChildNickname: String?,
    onOpenScanner: () -> Unit,
    onPickGallery: () -> Unit,
    onRedeemShortCode: (String) -> Unit,
    onOpenParentLogin: () -> Unit,
    onBack: () -> Unit,
    onSuccessBack: () -> Unit,
) {
    var manualMode by remember { mutableStateOf(false) }
    var manualCode by remember { mutableStateOf("") }
    val hint = cool.happyword.wordmagic.core.bindingFailureHint(failureReason)

    LaunchedEffect(boundChildNickname) {
        if (boundChildNickname != null) {
            manualMode = false
            manualCode = ""
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF8FAFC))
            .testTag("ScanBindingScreen"),
    ) {
        PageTopChrome(
            backButtonId = "ScanBindingTopBack",
            title = "扫码绑定家长账号",
            titleId = "ScanBindingTitle",
            onBack = onBack,
        )

        if (boundChildNickname != null) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        start = PageChromeInsets.bodyHorizontal,
                        end = PageChromeInsets.bodyHorizontal,
                        bottom = PageChromeInsets.bodyBottom,
                    ),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("🎉", fontSize = 48.sp, modifier = Modifier.testTag("ScanBindingSuccessEmoji"))
                Text(
                    "绑定成功，${boundChildNickname.ifBlank { "宝贝" }}！",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .padding(top = 8.dp)
                        .testTag("ScanBindingSuccessLabel"),
                )
                Button(
                    onClick = onSuccessBack,
                    modifier = Modifier
                        .padding(top = 24.dp)
                        .testTag("ScanBindingSuccessBack"),
                ) {
                    Text("返回首页")
                }
            }
        } else if (manualMode) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        start = PageChromeInsets.bodyHorizontal,
                        end = PageChromeInsets.bodyHorizontal,
                        bottom = PageChromeInsets.bodyBottom,
                    ),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text("输入家长网页显示的 6 位短码", fontSize = 14.sp, color = Color(0xFF475569))
                OutlinedTextField(
                    value = manualCode,
                    onValueChange = { manualCode = it.filter(Char::isDigit).take(6) },
                    label = { Text("000000") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth(0.6f)
                        .testTag("ScanBindingManualInput"),
                )
                Button(
                    onClick = { onRedeemShortCode(manualCode) },
                    enabled = !busy && manualCode.length == 6,
                    modifier = Modifier.testTag("ScanBindingManualSubmit"),
                ) {
                    Text(if (busy) "正在验证…" else "提交")
                }
                OutlinedButton(
                    onClick = {
                        manualMode = false
                        manualCode = ""
                    },
                    modifier = Modifier.testTag("ScanBindingManualBackToScan"),
                ) {
                    Text("返回扫码")
                }
                if (hint.isNotBlank()) {
                    Text(
                        hint,
                        color = Color(0xFFDC2626),
                        fontSize = 13.sp,
                        modifier = Modifier
                            .padding(top = 8.dp)
                            .testTag("ScanBindingFailureHint"),
                    )
                }
                ScanBindingParentLoginLink(
                    onOpenParentLogin = onOpenParentLogin,
                    testTag = "ScanBindingParentLoginLinkManual",
                )
                ScanBindingComplianceLinks()
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(
                        start = PageChromeInsets.bodyHorizontal,
                        end = PageChromeInsets.bodyHorizontal,
                        bottom = PageChromeInsets.bodyBottom,
                    ),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    "请扫描家长端「添加设备」页面显示的二维码",
                    fontSize = 14.sp,
                    color = Color(0xFF475569),
                    textAlign = TextAlign.Center,
                    modifier = Modifier.testTag("ScanBindingIdlePrompt"),
                )
                Button(
                    onClick = onOpenScanner,
                    enabled = !busy,
                    modifier = Modifier
                        .padding(top = 16.dp)
                        .testTag("ScanBindingScannerButton"),
                ) {
                    Text(if (busy) "正在打开扫码器…" else "打开扫码器")
                }
                OutlinedButton(
                    onClick = onPickGallery,
                    enabled = !busy,
                    modifier = Modifier.testTag("ScanBindingGalleryButton"),
                ) {
                    Text("📷 从图库选择二维码")
                }
                OutlinedButton(
                    onClick = { manualMode = true },
                    modifier = Modifier.testTag("ScanBindingManualToggle"),
                ) {
                    Text("无法扫码？手动输入短码")
                }
                if (hint.isNotBlank()) {
                    Text(
                        hint,
                        color = Color(0xFFDC2626),
                        fontSize = 13.sp,
                        modifier = Modifier
                            .padding(top = 16.dp)
                            .testTag("ScanBindingFailureHint"),
                    )
                }
                ScanBindingParentLoginLink(
                    onOpenParentLogin = onOpenParentLogin,
                    testTag = "ScanBindingParentLoginLink",
                )
                ScanBindingComplianceLinks()
            }
        }
    }
}

@Composable
fun BoundDeviceInfoScreen(
    credentials: CloudCredentials?,
    syncStatus: String,
    onEditProfile: suspend (String, String) -> String?,
    onUnbind: () -> Unit,
    onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var editOpen by remember { mutableStateOf(false) }
    var editNickname by remember(credentials?.bindingId) { mutableStateOf(credentials?.childNickname.orEmpty()) }
    var selectedAvatar by remember(credentials?.bindingId) { mutableStateOf(credentials?.avatarEmoji.orEmpty().ifBlank { "🦄" }) }
    var editError by remember { mutableStateOf("") }
    var editBusy by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf("") }
    val editFocusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF8FAFC))
            .verticalScroll(rememberScrollState())
            .topChromeSafeInsets()
            .padding(
                start = PageChromeInsets.bodyHorizontal,
                top = PageChromeInsets.bodyTop,
                end = PageChromeInsets.bodyHorizontal,
                bottom = PageChromeInsets.bodyBottom,
            )
            .testTag("BoundDeviceInfoScreen"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier.testTag("BoundDeviceInfoBackButton"),
            )
            Text(
                "家长账户",
                modifier = Modifier
                    .weight(1f)
                    .testTag("BoundDeviceInfoTitle"),
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF1D3557),
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.width(48.dp))
        }

        if (credentials == null) {
            Text("当前未绑定家长账号。", fontSize = 14.sp, color = Color(0xFF64748B), modifier = Modifier.padding(24.dp))
        } else {
            Column(
                modifier = Modifier
                    .padding(top = 16.dp)
                    .fillMaxWidth(0.9f)
                    .widthIn(max = 880.dp)
                    .align(Alignment.CenterHorizontally)
                    .background(Color.White, RoundedCornerShape(14.dp))
                    .padding(horizontal = 28.dp, vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                BoundInfoEditableNicknameRow(
                    credentials = credentials,
                    onEdit = {
                        editNickname = credentials.childNickname
                        selectedAvatar = credentials.avatarEmoji.ifBlank { "🦄" }
                        editError = ""
                        editOpen = true
                    },
                )
                BoundInfoRow("Family ID", credentials.familyLabel)
                BoundInfoRow("Binding ID", credentials.bindingId)
                BoundInfoRow("Device ID 末四位", credentials.deviceId.takeLast(4))
                BoundInfoRow("Device ID 来源", deviceIdSourceLabel(credentials.deviceIdSource))
                BoundInfoRow("绑定时间", formatPairedAt(credentials.pairedAtMs))
                if (toast.isNotBlank()) {
                    Text(toast, modifier = Modifier.padding(top = 4.dp).testTag("BoundDeviceInfoNicknameToast"), color = Color(0xFF1F2937))
                }
                Button(
                    onClick = onUnbind,
                    modifier = Modifier.fillMaxWidth().padding(top = 22.dp).height(58.dp).testTag("BoundDeviceInfoUnbind"),
                    shape = RoundedCornerShape(999.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050), contentColor = Color.White),
                ) {
                    Text("解除设备绑定", fontSize = 18.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }

    if (editOpen) {
        LaunchedEffect(Unit) {
            delay(120)
            editFocusRequester.requestFocus()
            keyboardController?.show()
        }
        Dialog(
            onDismissRequest = { if (!editBusy) editOpen = false },
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth(0.86f)
                    .widthIn(max = 860.dp)
                    .background(Color.White, RoundedCornerShape(20.dp))
                    .padding(horizontal = 20.dp, vertical = 24.dp)
                    .testTag("EditChildNicknameDialog"),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    "修改孩子的名字",
                    modifier = Modifier.align(Alignment.CenterHorizontally).testTag("EditChildNicknameDialogTitle"),
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color(0xFF1D3557),
                )
                Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    Text("名字", fontSize = 14.sp, color = Color(0xFF888888))
                    OutlinedTextField(
                        value = editNickname,
                        onValueChange = {
                            editNickname = it.take(32)
                            editError = ""
                        },
                        label = { Text("名字") },
                        enabled = !editBusy,
                        singleLine = true,
                        keyboardOptions = KeyboardOptions.Default,
                        modifier = Modifier
                            .fillMaxWidth()
                            .focusRequester(editFocusRequester)
                            .testTag("EditChildNicknameInput"),
                    )
                }
                Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    Text("头像", fontSize = 14.sp, color = Color(0xFF888888))
                    AvatarEmojiFlowRow {
                        childAvatarEmojiChoices(credentials?.avatarEmoji.orEmpty()).forEach { emoji ->
                            Box(
                                modifier = Modifier
                                    .size(44.dp)
                                    .background(
                                        if (selectedAvatar == emoji) Color(0xFFCDE8FF) else Color(0xFFF1F2F4),
                                        RoundedCornerShape(12.dp),
                                    )
                                    .border(
                                        width = if (selectedAvatar == emoji) 2.dp else 1.dp,
                                        color = if (selectedAvatar == emoji) Color(0xFF457B9D) else Color(0xFFE0E0E0),
                                        shape = RoundedCornerShape(12.dp),
                                    )
                                    .clickable(enabled = !editBusy) { selectedAvatar = emoji }
                                    .testTag("EditChildNicknameEmoji_$emoji"),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(emoji, style = circleGlyphTextStyle(22.sp))
                            }
                        }
                    }
                }
                if (editError.isNotBlank()) {
                    Text(editError, color = Color(0xFFE63946), modifier = Modifier.testTag("EditChildNicknameError"))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxWidth()) {
                    Button(
                        enabled = !editBusy,
                        onClick = { editOpen = false },
                        modifier = Modifier.weight(1f).height(44.dp).testTag("EditChildNicknameCancelButton"),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF1F2F4), contentColor = Color(0xFF1D3557)),
                        contentPadding = PaddingValues(0.dp),
                    ) {
                        Text("取消")
                    }
                    Button(
                        enabled = !editBusy,
                        onClick = {
                            val trimmed = editNickname.trim()
                            if (trimmed.isBlank()) {
                                editError = "请输入孩子的名字"
                                return@Button
                            }
                            scope.launch {
                                editBusy = true
                                val error = onEditProfile(trimmed, selectedAvatar)
                                editBusy = false
                                if (error == null) {
                                    toast = "已保存"
                                    editOpen = false
                                } else {
                                    editError = error
                                }
                            }
                        },
                        modifier = Modifier.weight(1f).height(44.dp).testTag("EditChildNicknameSubmitButton"),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050), contentColor = Color.White),
                        contentPadding = PaddingValues(0.dp),
                    ) {
                        Text(if (editBusy) "保存中..." else "保存")
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AvatarEmojiFlowRow(content: @Composable () -> Unit) {
    if (ChildAvatarEmojiWrapEnabled) {
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            content = { content() },
        )
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
            content()
        }
    }
}

@Composable
private fun BoundInfoEditableNicknameRow(credentials: CloudCredentials, onEdit: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("孩子档案", fontSize = 14.sp, color = Color(0xFF64748B), modifier = Modifier.width(112.dp))
        Text(
            "${credentials.avatarEmoji.ifBlank { "🦄" }} ${credentials.childNickname.ifBlank { "宝贝" }}",
            modifier = Modifier.weight(1f).testTag("BoundDeviceInfoNicknameValue"),
            fontSize = 14.sp,
            color = Color(0xFF1F2937),
        )
        Button(
            onClick = onEdit,
            modifier = Modifier.height(32.dp).testTag("BoundDeviceInfoNicknameEditButton"),
            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE2E8F0), contentColor = Color(0xFF1F2937)),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
        ) {
            Text("✏️ 编辑", fontSize = 12.sp)
        }
    }
}

@Composable
private fun BoundInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontSize = 14.sp, color = Color(0xFF64748B), modifier = Modifier.width(112.dp))
        Text(value.ifBlank { "—" }, fontSize = 14.sp, color = Color(0xFF1F2937), modifier = Modifier.weight(1f))
    }
}

private fun deviceIdSourceLabel(source: String): String = when (source) {
    "asset_store" -> "AssetStoreKit (持久)"
    else -> "本地 preferences (重装即丢)"
}

private fun formatPairedAt(ms: Long): String {
    if (ms <= 0L) return "—"
    return SimpleDateFormat("M/d/yyyy, h:mm:ss a", Locale.US).format(Date(ms))
}
