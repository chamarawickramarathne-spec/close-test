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
import okhttp3.Response
import org.json.JSONObject
import java.io.File
import java.io.IOException
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

    private const val ATTEMPTS = 3
    private const val DOWNLOAD_ATTEMPTS = 3
    private val APK_NAME = Regex("^[A-Za-z0-9._-]+\\.apk$")

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    fun check(): AppUpdate? {
        val manifest = runCatching { fetchManifest() }.getOrNull()
        if (manifest != null) {
            val versionCode = manifest.optInt("versionCode", 0)
            val apkName = manifest.optString("apk")
            if (versionCode > 0 && APK_NAME.matches(apkName)) {
                if (versionCode <= BuildConfig.VERSION_CODE) return null
                return AppUpdate(
                    versionCode = versionCode,
                    versionName = manifest.optString("versionName").ifBlank { "new version" },
                    apkUrl = AppConfig.UPDATE_DOWNLOAD_BASE + apkName,
                    apkSize = 0,
                    notes = manifest.optString("notes").trim()
                )
            }
        }
        return checkFromApi()
    }

    private fun checkFromApi(): AppUpdate? {
        val request = Request.Builder()
            .url(AppConfig.UPDATE_CHECK_URL)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", userAgent())
            .build()
        callWithRetry(request).use { response ->
            if (response.code == 404) return null
            if (!response.isSuccessful) throw UpdaterException(serverMessage(response.code))
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
                        manifest = runCatching {
                            JSONObject(fetchTextOrNull(asset.optString("browser_download_url")).orEmpty())
                        }.getOrNull()
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
            .header("User-Agent", userAgent())
            .build()
        var lastMessage: String? = null
        for (attempt in 0 until DOWNLOAD_ATTEMPTS) {
            try {
                downloadOnce(request, target, update.apkSize, onProgress)
                return target
            } catch (e: IOException) {
                lastMessage = "The update download was interrupted. Check your connection and try again."
            } catch (e: UpdaterException) {
                throw e
            }
            target.delete()
            if (attempt < DOWNLOAD_ATTEMPTS - 1) sleep(attempt)
        }
        throw UpdaterException(lastMessage ?: "The update download failed.")
    }

    private fun downloadOnce(
        request: Request,
        target: File,
        fallbackSize: Long,
        onProgress: (Int) -> Unit
    ) {
        callWithRetry(request).use { response ->
            if (!response.isSuccessful) throw UpdaterException(serverMessage(response.code))
            val body = response.body ?: throw UpdaterException("The update download was empty.")
            val total = if (body.contentLength() > 0) body.contentLength() else fallbackSize
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
            if (total > 0 && target.length() != total) {
                throw IOException("Incomplete download")
            }
        }
        if (target.length() <= 0L) throw UpdaterException("The downloaded update is empty.")
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

    private fun fetchManifest(): JSONObject? {
        val text = fetchTextOrNull(AppConfig.UPDATE_MANIFEST_URL) ?: return null
        return runCatching { JSONObject(text) }.getOrNull()
    }

    private fun fetchTextOrNull(url: String): String? {
        if (url.isBlank()) return null
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", userAgent())
            .build()
        callWithRetry(request).use { response ->
            if (response.code == 404) return null
            if (!response.isSuccessful) throw UpdaterException(serverMessage(response.code))
            return response.body?.string().orEmpty()
        }
    }

    private fun callWithRetry(request: Request): Response {
        var lastError: IOException? = null
        for (attempt in 0 until ATTEMPTS) {
            try {
                val response = client.newCall(request).execute()
                if (response.code in 500..599 && attempt < ATTEMPTS - 1) {
                    response.close()
                    sleep(attempt)
                    continue
                }
                return response
            } catch (e: IOException) {
                lastError = e
                if (attempt == ATTEMPTS - 1) throw e
                sleep(attempt)
            }
        }
        throw lastError ?: UpdaterException("The update server is unavailable. Try again in a minute.")
    }

    private fun serverMessage(code: Int): String =
        if (code in 500..599) {
            "The update server is busy ($code). Try again in a minute."
        } else {
            "The update server answered $code."
        }

    private fun userAgent(): String = "TesterLoop-Mobile/${BuildConfig.VERSION_NAME}"

    private fun sleep(attempt: Int) {
        runCatching { Thread.sleep(700L * (attempt + 1)) }
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
