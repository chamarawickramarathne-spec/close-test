package lk.closetester.helper.ui

import lk.closetester.helper.core.AppConfig
import lk.closetester.helper.core.isActiveCampaign
import lk.closetester.helper.data.api.ReportInstallRequest
import lk.closetester.helper.data.api.TesterDashboard
import lk.closetester.helper.data.api.orThrow
import lk.closetester.helper.data.local.InstallDates
import lk.closetester.helper.data.local.TrackedCampaign
import lk.closetester.helper.worker.UsageReader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import retrofit2.HttpException

internal data class InstallCapture(
    val installed: Boolean,
    val synced: Boolean
)

internal suspend fun AppVm.captureInstallTracking(dash: TesterDashboard) {
    val testerId = dash.tester?.id ?: return
    val tracked = dash.mine
        .filter { isActiveCampaign(it.campaignState) }
        .filter { it.state == "joined" || it.state == "opted_in" }
        .map {
            TrackedCampaign(
                campaignId = it.campaignId,
                appName = it.appName,
                packageName = it.packageName,
                state = it.campaignState
            )
        }
    installStore.saveTracked(testerId, tracked)

    val today = InstallDates.today()
    for (item in tracked) {
        val packageName = item.packageName?.takeIf { it.isNotBlank() } ?: continue
        val installed = withContext(Dispatchers.IO) {
            UsageReader.isInstalled(appContext, packageName)
        }
        installStore.record(item.campaignId, today, installed)
    }
}

internal suspend fun AppVm.captureInstallNow(
    campaignId: String,
    source: String
): InstallCapture? {
    val item = ui.value.mine.firstOrNull { it.campaignId == campaignId } ?: return null
    val packageName = item.packageName?.takeIf { it.isNotBlank() } ?: return null
    val installed = withContext(Dispatchers.IO) {
        UsageReader.isInstalled(appContext, packageName)
    }
    val today = InstallDates.today()
    installStore.record(campaignId, today, installed)
    val synced = try {
        session.withAuth { token ->
            api.reportAppInstallDaily(
                AppConfig.SUPABASE_ANON_KEY,
                "Bearer $token",
                ReportInstallRequest(
                    campaignId = campaignId,
                    date = today,
                    installed = installed,
                    source = source
                )
            ).orThrow()
        }
        installStore.markSynced(campaignId, today)
        true
    } catch (e: HttpException) {
        if (e.code() == 401) throw e
        false
    }
    return InstallCapture(installed = installed, synced = synced)
}
