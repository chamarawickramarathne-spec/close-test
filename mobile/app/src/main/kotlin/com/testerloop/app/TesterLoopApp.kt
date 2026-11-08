package com.testerloop.app

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Constraints
import androidx.work.Configuration
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.testerloop.app.worker.DailyInstallCheckWorker
import com.testerloop.app.worker.UsageSyncWorker
import dagger.hilt.android.HiltAndroidApp
import java.util.concurrent.TimeUnit
import javax.inject.Inject

@HiltAndroidApp
class TesterLoopApp : Application(), Configuration.Provider {
    @Inject lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        scheduleUsageSync()
        scheduleInstallCheck()
    }

    private fun scheduleInstallCheck() {
        val manager = WorkManager.getInstance(this)
        manager.enqueueUniquePeriodicWork(
            "testerloop-install-check",
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<DailyInstallCheckWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(10, TimeUnit.MINUTES)
                .build()
        )
        manager.enqueueUniqueWork(
            "testerloop-install-check-now",
            ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<DailyInstallCheckWorker>().build()
        )
    }

    private fun scheduleUsageSync() {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val manager = WorkManager.getInstance(this)
        manager.enqueueUniquePeriodicWork(
            "testerloop-usage-sync",
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<UsageSyncWorker>(1, TimeUnit.DAYS)
                .setConstraints(constraints)
                .setInitialDelay(15, TimeUnit.MINUTES)
                .build()
        )
        manager.enqueueUniqueWork(
            "testerloop-usage-sync-now",
            ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<UsageSyncWorker>()
                .setConstraints(constraints)
                .build()
        )
    }
}
