package cool.happyword.wordmagic.app

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.util.Calendar
import java.util.Locale

object BuildInfo {
    /** Formats epoch millis as YYMMDDHHmm in the device's local time (Harmony parity). */
    fun formatBuildTimestamp(epochMs: Long): String {
        val cal = Calendar.getInstance(Locale.getDefault())
        cal.timeInMillis = epochMs
        val yy = (cal.get(Calendar.YEAR) % 100).toString().padStart(2, '0')
        val mm = (cal.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
        val dd = cal.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
        val hh = cal.get(Calendar.HOUR_OF_DAY).toString().padStart(2, '0')
        val mn = cal.get(Calendar.MINUTE).toString().padStart(2, '0')
        return "$yy$mm$dd$hh$mn"
    }

    /** `v{versionName}({timestamp})` using install/update time from PackageManager. */
    fun homeVersionLabel(context: Context): String {
        val pm = context.packageManager
        val pkg = context.packageName
        val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(pkg, 0)
        }
        val name = pi.versionName?.takeIf { it.isNotBlank() } ?: "?.?.?"
        val ms = pi.lastUpdateTime.takeIf { it > 0L } ?: System.currentTimeMillis()
        return "v$name(${formatBuildTimestamp(ms)})"
    }
}
