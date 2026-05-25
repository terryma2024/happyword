package cool.happyword.wordmagic.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent

enum class BrowserLaunchMode {
    AndroidCustomTabs,
}

data class BrowserLaunchSpec(
    val url: String,
    val mode: BrowserLaunchMode,
)

object SystemBrowser {
    fun launchSpec(url: String): BrowserLaunchSpec {
        return BrowserLaunchSpec(url, BrowserLaunchMode.AndroidCustomTabs)
    }

    fun browserIntent(spec: BrowserLaunchSpec): Intent {
        return CustomTabsIntent.Builder()
            .setShowTitle(true)
            .build()
            .intent
            .apply {
                data = Uri.parse(spec.url)
            }
    }

    fun openUrl(context: Context, url: String) {
        context.startActivity(browserIntent(launchSpec(url)))
    }
}
