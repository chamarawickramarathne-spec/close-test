package com.testerloop.app.worker

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings

data class UsageTotals(
    val foregroundMs: Long,
    val sessions: Int
)

object UsageReader {
    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun usageAccessIntent(): Intent =
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun isInstalled(context: Context, packageName: String): Boolean {
        if (packageName.isBlank()) return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
            } else {
                context.packageManager.getPackageInfo(packageName, 0)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun readUsage(context: Context, packageName: String, startMs: Long, endMs: Long): UsageTotals {
        if (packageName.isBlank() || endMs <= startMs) return UsageTotals(0, 0)
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(startMs, endMs)
        val event = UsageEvents.Event()
        val resumedType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            UsageEvents.Event.ACTIVITY_RESUMED
        } else {
            UsageEvents.Event.MOVE_TO_FOREGROUND
        }
        val pausedType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            UsageEvents.Event.ACTIVITY_PAUSED
        } else {
            UsageEvents.Event.MOVE_TO_BACKGROUND
        }

        var foreground = 0L
        var sessions = 0
        var resumedAt = -1L

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.packageName != packageName) continue
            when (event.eventType) {
                resumedType -> {
                    if (resumedAt < 0) {
                        resumedAt = event.timeStamp
                        sessions++
                    }
                }
                pausedType -> {
                    if (resumedAt >= 0) {
                        foreground += (event.timeStamp - resumedAt).coerceAtLeast(0)
                        resumedAt = -1
                    }
                }
            }
        }
        if (resumedAt >= 0) {
            foreground += (endMs - resumedAt).coerceAtLeast(0)
        }

        return UsageTotals(
            foregroundMs = foreground.coerceAtMost(endMs - startMs),
            sessions = sessions
        )
    }
}
