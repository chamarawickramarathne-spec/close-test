package com.testerloop.app.core

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import com.testerloop.app.BuildConfig
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

data class AppUpdate(
    val versionCode: Int,
    val versionName: String,
    val apkUrl: String,
    val apkSize: Long,
    val notes: String
)

class UpdaterException(message: String) : Exception(message)

object AppUpdater {

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    fun check(): AppUpdate? {
        val request = Request.Builder()
            .url(AppConfig.UPDATE_CHECK_URL)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "TesterLoop-Mobile/${BuildConfig.VERSION_NAME}")
            .build()
        client.newCall(request).execute().use { response ->
            if (response.code == 404) return null
            if (!response.isSuccessful) {
                throw UpdaterException("The update server answered ${response.code}.")
            }
            val body = response.body?.string().orEmpty()
            val json = JSONObject(body)
            if (json.optBoolean("draft", false)) return null
            val tag = json.optString("tag_name")
            val notes = json.optString("body").trim()

            val assets = json.optJSONArray("assets") ?: return null
            var apkUrl: String? = null
            var apkSize = 0L
            var manifest: JSONObject? = null
            for (i in 0 until assets.length()) {
                val asset = assets.getJSONObject(i)
                val name = asset.optString("name")
                when {
                    name.equals("mobile-version.json", true) ->
                        manifest = runCatching { JSONObject(asset.optString("browser_download_url").let { url -> fetchText(url) }) }.getOrNull()
                    name.endsWith(".apk", true) -> {
                        apkUrl = asset.optString("browser_download_url")
                        apkSize = asset.optLong("size")
                    }
                }
            }
            val downloadUrl = apkUrl ?: return null

            val manifestCode = manifest?.optInt("versionCode", 0) ?: 0
            val manifestName = manifest?.optString("versionName").orEmpty()
            val tagVersion = parseVersion(tag)
            val versionCode = when {
                manifestCode > 0 -> manifestCode
                else -> versionCodeOf(tagVersion)
            }
            val versionName = manifestName.ifBlank {
                tagVersion?.let { "${it.first}.${it.second}.${it.third}" }
                    ?: tag.substringAfterLast("v", tag).ifBlank { "new version" }
            }
            if (versionCode <= BuildConfig.VERSION_CODE) return null
            return AppUpdate(
                versionCode = versionCode,
                versionName = versionName,
                apkUrl = downloadUrl,
                apkSize = apkSize,
                notes = notes
            )
        }
    }

    fun download(context: Context, update: AppUpdate, onProgress: (Int) -> Unit): File {
        val dir = File(context.cacheDir, "updates").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val target = File(dir, "TesterLoop-${update.versionName}.apk")
        val request = Request.Builder()
            .url(update.apkUrl)
            .header("User-Agent", "TesterLoop-Mobile/${BuildConfig.VERSION_NAME}")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw UpdaterException("The update download failed with ${response.code}.")
            }
            val body = response.body ?: throw UpdaterException("The update download was empty.")
            val total = if (body.contentLength() > 0) body.contentLength() else update.apkSize
            body.byteStream().use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var read = 0L
                    var lastPercent = -1
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        read += count
                        if (total > 0) {
                            val percent = ((read * 100) / total).toInt().coerceIn(0, 100)
                            if (percent != lastPercent) {
                                lastPercent = percent
                                onProgress(percent)
                            }
                        }
                    }
                }
            }
        }
        if (target.length() <= 0L) throw UpdaterException("The downloaded update is empty.")
        return target
    }

    fun canInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()

    fun install(context: Context, apk: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    fun installPermissionIntent(context: Context): Intent =
        Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${context.packageName}")
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun fetchText(url: String): String {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "TesterLoop-Mobile/${BuildConfig.VERSION_NAME}")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw UpdaterException("The version manifest answered ${response.code}.")
            return response.body?.string().orEmpty()
        }
    }

    private fun parseVersion(tag: String): Triple<Int, Int, Int>? {
        val match = Regex("(\\d+)\\.(\\d+)\\.(\\d+)").find(tag) ?: return null
        return Triple(
            match.groupValues[1].toIntOrNull() ?: return null,
            match.groupValues[2].toIntOrNull() ?: return null,
            match.groupValues[3].toIntOrNull() ?: return null
        )
    }

    private fun versionCodeOf(version: Triple<Int, Int, Int>?): Int {
        if (version == null) return 0
        return version.first * 10_000 + version.second * 100 + version.third
    }
}
