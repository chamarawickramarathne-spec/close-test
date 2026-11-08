package com.testerloop.app.ui

import android.os.Build
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.lifecycle.viewModelScope
import androidx.work.WorkManager
import com.testerloop.app.core.AppConfig
import com.testerloop.app.core.GroupLink
import com.testerloop.app.core.PlayLink
import com.testerloop.app.core.installedBuildLabel
import com.testerloop.app.core.isActiveCampaign
import com.testerloop.app.data.api.FileReportRequest
import com.testerloop.app.data.api.SetOptInRequest
import com.testerloop.app.data.api.orThrow
import com.testerloop.app.data.local.SessionExpiredException
import com.testerloop.app.worker.UsageReader
import com.testerloop.app.worker.UsageSyncWorker
import kotlinx.coroutines.launch
import retrofit2.HttpException

fun AppVm.join(campaignId: String) {
    if (ui.value.joiningId != null || ui.value.phase != Phase.Ready) return
    val seatsFree = ui.value.available.firstOrNull { it.campaignId == campaignId }?.seatsFree
    if (seatsFree != null && seatsFree <= 0) {
        message("This project has no tester seats left.")
        return
    }
    updateState { it.copy(joiningId = campaignId) }
    viewModelScope.launch {
        try {
            session.withAuth { token ->
                api.joinCampaign(
                    AppConfig.SUPABASE_ANON_KEY,
                    "Bearer $token",
                    mapOf("p_campaign_id" to campaignId)
                ).orThrow()
            }
            loadDashboard(initial = false)
            val joined = ui.value.mine.firstOrNull { it.campaignId == campaignId }
            if (joined != null) {
                captureInstallNow(campaignId, "mobile_daily")
                val url = GroupLink.url(joined.groupName)
                if (url != null) {
                    sendEvent(UiEvent.OpenUrl(url))
                } else {
                    message("You joined. Open the project to see its Google Group.")
                }
                message("Joined ${joined.appName ?: "the project"}.")
            } else {
                message("You joined the project.")
            }
        } catch (e: Exception) {
            handleActionError(e)
        } finally {
            updateState { it.copy(joiningId = null) }
        }
    }
}

fun AppVm.confirmOptIn(campaignId: String) {
    val item = ui.value.mine.firstOrNull { it.campaignId == campaignId } ?: return
    if (item.optInVerification == "google_group") {
        message("This opt-in is already confirmed.")
        return
    }
    if (!UsageReader.hasUsageAccess(appContext)) {
        refreshUsageAccess()
        message("Allow usage access before confirming opt-in. Open this project again after enabling it.")
        return
    }
    if (ui.value.optInBusyId != null) return
    updateState { it.copy(optInBusyId = campaignId) }
    viewModelScope.launch {
        try {
            val result = session.withAuth { token ->
                api.verifyOptIn(
                    AppConfig.SUPABASE_ANON_KEY,
                    "Bearer $token",
                    mapOf("campaign_id" to campaignId)
                )
            }
            val status = (result["status"] as? String)?.lowercase()
            val ok = (result["state"] as? String) == "opted_in" ||
                (result["opt_in_verification"] as? String) == "google_group" ||
                (result["ok"] as? Boolean) == true || status == "active"
            if (ok) {
                loadDashboard(initial = false)
                captureInstallNow(campaignId, "mobile_daily")
                val playUrl = ui.value.mine
                    .firstOrNull { it.campaignId == campaignId }
                    ?.playOptInUrl
                if (playUrl != null && PlayLink.isValid(playUrl)) {
                    message("Google Group membership confirmed. Opening the Play test.")
                    sendEvent(UiEvent.OpenUrl(playUrl))
                } else {
                    message("Google Group membership confirmed.")
                }
            } else {
                loadDashboard(initial = false)
                val reason = (result["message"] as? String)
                    ?: (result["error"] as? String)
                    ?: "We could not confirm your Google Group membership."
                message(reason)
            }
        } catch (e: HttpException) {
            if (e.code() == 404) {
                message("Opt-in checking is not deployed on the server yet. Contact operations.")
            } else {
                loadDashboard(initial = false)
                handleActionError(e)
            }
        } catch (e: SessionExpiredException) {
            handleActionError(e)
        } catch (e: Exception) {
            loadDashboard(initial = false)
            handleActionError(e)
        } finally {
            updateState { it.copy(optInBusyId = null) }
        }
    }
}

fun AppVm.optOut(campaignId: String) {
    if (ui.value.optInBusyId != null) return
    updateState { it.copy(optInBusyId = campaignId) }
    viewModelScope.launch {
        try {
            session.withAuth { token ->
                api.setOptIn(
                    AppConfig.SUPABASE_ANON_KEY,
                    "Bearer $token",
                    SetOptInRequest(campaignId = campaignId, optedIn = false)
                ).orThrow()
            }
            updateState { it.copy(campaignId = null) }
            loadDashboard(initial = false)
            sendEvent(UiEvent.CloseCampaign)
            message("You opted out. Your 14-day clock for this project starts again if you rejoin.")
        } catch (e: Exception) {
            handleActionError(e)
        } finally {
            updateState { it.copy(optInBusyId = null) }
        }
    }
}

fun AppVm.openPlay(campaignId: String) {
    val item = ui.value.mine.firstOrNull { it.campaignId == campaignId }
    val url = item?.playOptInUrl
    if (!PlayLink.isValid(url)) {
        message("The Play test link is not ready yet. Contact operations.")
        return
    }
    sendEvent(UiEvent.OpenUrl(url!!))
}

fun AppVm.checkInstall(campaignId: String) {
    val item = ui.value.mine.firstOrNull { it.campaignId == campaignId } ?: return
    if (!isActiveCampaign(item.campaignState)) {
        message("This project is closed. Daily install checks have stopped.")
        return
    }
    val packageName = item.packageName?.takeIf { it.isNotBlank() }
    if (packageName == null) {
        message("This project has no package name yet. Contact operations.")
        return
    }
    viewModelScope.launch {
        try {
            val capture = captureInstallNow(campaignId, "mobile_manual")
            if (capture == null) {
                message("This project has no package name yet. Contact operations.")
                return@launch
            }
            loadDashboard(initial = false)
            message(
                when {
                    capture.installed && capture.synced ->
                        "Installed app found and recorded for today."
                    capture.installed ->
                        "Installed app found. Today's check is saved on this phone and will sync."
                    capture.synced ->
                        "This app is not installed on this device today."
                    else ->
                        "This app is not installed. The check is saved on this phone and will sync."
                }
            )
        } catch (e: Exception) {
            handleActionError(e)
        }
    }
}

fun AppVm.openUsageSettings() = sendEvent(UiEvent.OpenUsageSettings)

fun AppVm.syncUsageNow() {
    val constraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()
    val request = OneTimeWorkRequestBuilder<UsageSyncWorker>()
        .setConstraints(constraints)
        .build()
    WorkManager.getInstance(appContext).enqueueUniqueWork(
        "testerloop-usage-sync-manual",
        ExistingWorkPolicy.REPLACE,
        request
    )
    message("Usage sync queued.")
}

fun AppVm.submitReport(
    campaignId: String,
    severity: String,
    title: String,
    body: String
) {
    val state = ui.value
    if (state.reportBusy) return
    val cleanTitle = title.trim()
    val cleanBody = body.trim()
    if (cleanTitle.length < 4) {
        updateState { it.copy(reportError = "Give the report a title of at least four characters.") }
        return
    }
    if (cleanBody.isEmpty()) {
        updateState { it.copy(reportError = "Describe what happened.") }
        return
    }
    updateState { it.copy(reportBusy = true, reportError = null) }
    viewModelScope.launch {
        try {
            val device = listOf(Build.MANUFACTURER, Build.MODEL)
                .filter { it.isNotBlank() }
                .joinToString(" ")
            val packageName = state.mine.firstOrNull { it.campaignId == campaignId }?.packageName
            val buildLabel = installedBuildLabel(appContext, packageName)
            session.withAuth { token ->
                api.fileReport(
                    AppConfig.SUPABASE_ANON_KEY,
                    "Bearer $token",
                    FileReportRequest(
                        campaignId = campaignId,
                        severity = severity,
                        title = cleanTitle,
                        body = cleanBody,
                        buildLabel = buildLabel,
                        device = device.ifBlank { null }
                    )
                ).orThrow()
            }
            updateState { it.copy(reportSuccess = it.reportSuccess + 1) }
            loadDashboard(initial = false)
            message("Report filed. Operations will review it.")
        } catch (e: Exception) {
            updateState { it.copy(reportError = com.testerloop.app.data.api.apiMessage(e)) }
            if (e is SessionExpiredException) handleActionError(e)
        } finally {
            updateState { it.copy(reportBusy = false) }
        }
    }
}

fun AppVm.clearReportError() = updateState { it.copy(reportError = null) }





