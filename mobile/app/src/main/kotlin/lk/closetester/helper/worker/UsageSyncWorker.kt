package lk.closetester.helper.worker

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import lk.closetester.helper.core.AppConfig
import lk.closetester.helper.core.isActiveCampaign
import lk.closetester.helper.data.api.ReportInstallRequest
import lk.closetester.helper.data.api.RpcRequest
import lk.closetester.helper.data.api.SupabaseApi
import lk.closetester.helper.data.api.orThrow
import lk.closetester.helper.data.local.InstallDates
import lk.closetester.helper.data.local.InstallHistoryStore
import lk.closetester.helper.data.local.SessionExpiredException
import lk.closetester.helper.data.local.SessionManager
import lk.closetester.helper.data.local.TrackedCampaign
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import retrofit2.HttpException

@HiltWorker
class UsageSyncWorker @AssistedInject constructor(
    @Assisted ctx: Context,
    @Assisted params: WorkerParameters,
    private val api: SupabaseApi,
    private val session: SessionManager,
    private val installStore: InstallHistoryStore
) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val context = applicationContext
        val hasUsageAccess = UsageReader.hasUsageAccess(context)

        return try {
            session.withAuth { token ->
                val auth = "Bearer $token"
                val dash = api.testerDashboard(AppConfig.SUPABASE_ANON_KEY, auth)
                val active = dash.mine.filter {
                    isActiveCampaign(it.campaignState) &&
                        (it.state == "joined" || it.state == "opted_in") &&
                        !it.packageName.isNullOrBlank()
                }

                dash.tester?.id?.let { testerId ->
                    installStore.saveTracked(
                        testerId,
                        active.map {
                            TrackedCampaign(
                                campaignId = it.campaignId,
                                appName = it.appName,
                                packageName = it.packageName,
                                state = it.campaignState
                            )
                        }
                    )
                }

                val today = InstallDates.today()
                for (item in active) {
                    val packageName = item.packageName!!.takeIf { it.isNotBlank() } ?: continue
                    val installed = UsageReader.isInstalled(context, packageName)
                    installStore.record(item.campaignId, today, installed)
                }

                uploadPendingInstalls(auth)

                if (!hasUsageAccess) return@withAuth
                val todayStart = startOfToday()
                val yesterdayStart = dayBefore(todayStart)
                val now = System.currentTimeMillis()
                val days = listOf(yesterdayStart to todayStart - 1, todayStart to now)

                for (item in active) {
                    val packageName = item.packageName!!.takeIf { it.isNotBlank() } ?: continue
                    for ((start, end) in days) {
                        if (end <= start) continue
                        val totals = UsageReader.readUsage(context, packageName, start, end)
                        api.reportAppUsageDaily(
                            AppConfig.SUPABASE_ANON_KEY,
                            auth,
                            RpcRequest(
                                pCampaignId = item.campaignId,
                                pDate = dateKey(start),
                                pForegroundMs = totals.foregroundMs,
                                pSessions = totals.sessions
                            )
                        ).orThrow()
                    }
                }
            }
            Result.success()
        } catch (_: SessionExpiredException) {
            Result.success()
        } catch (e: HttpException) {
            if (e.code() in 400..499) Result.success() else Result.retry()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    private suspend fun uploadPendingInstalls(auth: String) {
        for (record in installStore.pending()) {
            try {
                api.reportAppInstallDaily(
                    AppConfig.SUPABASE_ANON_KEY,
                    auth,
                    ReportInstallRequest(
                        campaignId = record.campaignId,
                        date = record.date,
                        installed = record.installed,
                        source = "mobile_daily"
                    )
                ).orThrow()
                installStore.markSynced(record.campaignId, record.date)
            } catch (e: HttpException) {
                if (e.code() == 401) throw e
                if (e.code() in 400..499) {
                    installStore.markSynced(record.campaignId, record.date)
                } else {
                    throw e
                }
            }
        }
    }

    private fun startOfToday(): Long {
        val cal = Calendar.getInstance()
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun dayBefore(timestamp: Long): Long {
        val cal = Calendar.getInstance()
        cal.timeInMillis = timestamp
        cal.add(Calendar.DAY_OF_YEAR, -1)
        return cal.timeInMillis
    }

    private fun dateKey(timestamp: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(timestamp))
}
