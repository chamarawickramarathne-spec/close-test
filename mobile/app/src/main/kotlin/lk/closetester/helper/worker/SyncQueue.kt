package lk.closetester.helper.worker

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

internal fun enqueueUsageSync(context: Context) {
    val constraints = androidx.work.Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()
    WorkManager.getInstance(context).enqueueUniqueWork(
        "testerloop-usage-sync-now",
        ExistingWorkPolicy.KEEP,
        OneTimeWorkRequestBuilder<UsageSyncWorker>()
            .setConstraints(constraints)
            .build()
    )
}
