package cool.happyword.wordmagic.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Shared top navigation chrome aligned with HarmonyOS [PageTopChrome]:
 * circular leading back and optional centered title.
 */
@Composable
fun PageTopChrome(
    backButtonId: String,
    title: String,
    titleId: String,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth().topChromeSafeInsets()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = PageChromeInsets.bodyHorizontal, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier.testTag(backButtonId),
            )
            if (title.isNotBlank()) {
                Text(
                    text = title,
                    modifier = Modifier
                        .weight(1f)
                        .testTag(titleId),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF1F2937),
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.width(48.dp))
            } else {
                Spacer(Modifier.weight(1f))
            }
        }
    }
}
