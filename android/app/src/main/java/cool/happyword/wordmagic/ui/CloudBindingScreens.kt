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
import androidx.compose.foundation.text.KeyboardOptions
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
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cool.happyword.wordmagic.core.CloudCredentials

@Composable
fun ScanBindingScreen(
    deviceId: String,
    error: String,
    onRedeem: (String) -> Unit,
    onBack: () -> Unit,
) {
    var code by remember { mutableStateOf("") }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFFF6E7))
            .padding(horizontal = 44.dp, vertical = 22.dp)
            .testTag("ScanBindingScreen"),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("扫码绑定家长账号", fontSize = 30.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
        Text("设备 ${deviceId.takeLast(8)}", color = Color(0xFF6A5843), modifier = Modifier.padding(top = 8.dp))
        OutlinedTextField(
            value = code,
            onValueChange = { code = it.take(12) },
            label = { Text("输入绑定码") },
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, keyboardType = KeyboardType.Text),
            modifier = Modifier.padding(top = 18.dp).testTag("ScanBindingManualCodeInput"),
        )
        if (error.isNotBlank()) {
            Text(error, color = Color(0xFFD94141), modifier = Modifier.padding(top = 8.dp).testTag("ScanBindingError"))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 18.dp)) {
            OutlinedButton(onClick = onBack) { Text("返回") }
            OutlinedButton(onClick = {}, modifier = Modifier.testTag("ScanBindingGalleryButton")) { Text("相册") }
            OutlinedButton(onClick = {}, modifier = Modifier.testTag("ScanBindingCameraButton")) { Text("扫码") }
            Button(
                onClick = { onRedeem(code) },
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050)),
                modifier = Modifier.testTag("ScanBindingRedeemButton"),
            ) { Text("绑定") }
        }
    }
}

@Composable
fun BoundDeviceInfoScreen(
    credentials: CloudCredentials?,
    syncStatus: String,
    onManualSync: () -> Unit,
    onUnbind: () -> Unit,
    onBack: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(horizontal = 44.dp, vertical = 22.dp)
            .testTag("BoundDeviceInfoScreen"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("绑定设备", fontSize = 30.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = onBack) { Text("返回") }
        }
        Text(
            "${credentials?.avatarEmoji ?: "🦁"} ${credentials?.childNickname ?: "未绑定"}",
            modifier = Modifier.padding(top = 24.dp).testTag("BoundDeviceInfoNickname"),
            fontSize = 26.sp,
            fontWeight = FontWeight.Black,
            color = Color(0xFF303030),
        )
        Text("家庭：${credentials?.familyLabel ?: "-"}", color = Color(0xFF6A5843), modifier = Modifier.padding(top = 8.dp))
        Text("设备：${credentials?.deviceId?.takeLast(8) ?: "-"}", color = Color(0xFF6A5843), modifier = Modifier.padding(top = 8.dp))
        Text("同步：$syncStatus", modifier = Modifier.padding(top = 8.dp).testTag("BoundDeviceInfoSyncStatus"), color = Color(0xFF6A5843))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 24.dp)) {
            Button(onClick = onManualSync, modifier = Modifier.testTag("BoundDeviceInfoManualSync"), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050))) {
                Text("立即同步")
            }
            OutlinedButton(onClick = onUnbind, modifier = Modifier.testTag("BoundDeviceInfoUnbind")) {
                Text("解除绑定")
            }
        }
    }
}
