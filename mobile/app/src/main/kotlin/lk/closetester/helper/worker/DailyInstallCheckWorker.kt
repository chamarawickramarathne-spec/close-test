package lk.closetester.helper.worker

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import lk.closetester.helper.core.isActiveCampaign
import lk.closetester.helper.data.local.InstallDates
import lk.closetester.helper.data.local.InstallHistoryStore
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

@HiltWorker
class DailyInstallCheckWorker @AssistedInject constructor(
    @Assisted ctx: Context,
    @Assisted params: WorkerParameters,
    private val store: InstallHistoryStore
) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val tracked = store.tracked()
        if (tracked.isEmpty()) return Result.success()

        val today = InstallDates.today()
        for (item in tracked) {
            if (!isActiveCampaign(item.state)) continue
            val packageName = item.packageName?.takeIf { it.isNotBlank() } ?: continue
            val installed = UsageReader.isInstalled(context, packageName)
            store.record(item.campaignId, today, installed)
        }

        store.pruneSyncedBefore(InstallDates.daysAgo(45))
        enqueueUsageSync(context)
        return Result.success()
    }
}
