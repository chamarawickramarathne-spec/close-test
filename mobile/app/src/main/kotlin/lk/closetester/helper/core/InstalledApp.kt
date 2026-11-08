package lk.closetester.helper.core

import android.content.Context
import android.content.pm.PackageManager

fun installedBuildLabel(context: Context, packageName: String?): String? {
    val name = packageName?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    return try {
        @Suppress("DEPRECATION")
        val info = context.packageManager.getPackageInfo(name, 0)
        val versionName = info.versionName?.trim()?.takeIf { it.isNotEmpty() }
        @Suppress("DEPRECATION")
        val versionCode = info.versionCode
        if (versionName != null) "$versionName ($versionCode)" else versionCode.toString()
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }
}
