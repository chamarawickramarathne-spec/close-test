package com.testerloop.app.data.local

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton

private val Context.installDataStore by preferencesDataStore("testerloop_install")

data class TrackedCampaign(
    val campaignId: String,
    val appName: String?,
    val packageName: String?,
    val state: String?
)

data class DailyInstallRecord(
    val campaignId: String,
    val date: String,
    val installed: Boolean,
    val synced: Boolean,
    val checkedAt: Long
)

object InstallDates {
    private val format = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    fun today(): String = format.format(Date())

    fun daysAgo(days: Int): String {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, -days)
        return format.format(cal.time)
    }
}

@Singleton
class InstallHistoryStore @Inject constructor(@ApplicationContext private val context: Context) {
    private val trackedKey = stringPreferencesKey("tracked_campaigns")
    private val recordsKey = stringPreferencesKey("daily_records")
    private val testerKey = stringPreferencesKey("tester_id")
    private val mutex = Mutex()

    suspend fun saveTracked(testerId: String, campaigns: List<TrackedCampaign>) {
        mutex.withLock {
            context.installDataStore.edit { prefs ->
                val previous = prefs[testerKey]
                if (previous != null && previous != testerId) {
                    prefs.remove(recordsKey)
                }
                if (previous != testerId) {
                    prefs[testerKey] = testerId
                }
                prefs[trackedKey] = encodeTracked(campaigns).toString()
            }
        }
    }

    suspend fun tracked(): List<TrackedCampaign> {
        val raw = context.installDataStore.data.first()[trackedKey] ?: return emptyList()
        return runCatching { decodeTracked(JSONArray(raw)) }.getOrDefault(emptyList())
    }

    suspend fun record(campaignId: String, date: String, installed: Boolean) {
        mutex.withLock {
            context.installDataStore.edit { prefs ->
                val records = decodeRecords(prefs[recordsKey])
                records.put(
                    key(campaignId, date),
                    JSONObject()
                        .put("campaign_id", campaignId)
                        .put("date", date)
                        .put("installed", installed)
                        .put("synced", false)
                        .put("checked_at", System.currentTimeMillis())
                )
                prefs[recordsKey] = records.toString()
            }
        }
    }

    suspend fun pending(limit: Int = 30): List<DailyInstallRecord> {
        val raw = context.installDataStore.data.first()[recordsKey] ?: return emptyList()
        val records = decodeRecords(raw)
        val result = mutableListOf<DailyInstallRecord>()
        records.keys().forEach { k ->
            val item = records.optJSONObject(k) ?: return@forEach
            toRecord(item)?.let { result.add(it) }
        }
        return result
            .filter { !it.synced }
            .sortedByDescending { it.date }
            .take(limit)
    }

    suspend fun markSynced(campaignId: String, date: String) {
        mutex.withLock {
            context.installDataStore.edit { prefs ->
                val records = decodeRecords(prefs[recordsKey])
                val existing = records.optJSONObject(key(campaignId, date)) ?: return@edit
                existing.put("synced", true)
                records.put(key(campaignId, date), existing)
                prefs[recordsKey] = records.toString()
            }
        }
    }

    suspend fun pruneSyncedBefore(date: String) {
        mutex.withLock {
            context.installDataStore.edit { prefs ->
                val records = decodeRecords(prefs[recordsKey])
                val kept = JSONObject()
                records.keys().forEach { k ->
                    val item = records.optJSONObject(k) ?: return@forEach
                    val synced = item.optBoolean("synced", false)
                    val day = item.optString("date", "")
                    if (!synced || day >= date) {
                        kept.put(k, item)
                    }
                }
                prefs[recordsKey] = kept.toString()
            }
        }
    }

    private fun key(campaignId: String, date: String) = "$campaignId|$date"

    private fun encodeTracked(campaigns: List<TrackedCampaign>): JSONArray {
        val array = JSONArray()
        campaigns.forEach { item ->
            array.put(
                JSONObject()
                    .put("campaign_id", item.campaignId)
                    .put("app_name", item.appName)
                    .put("package_name", item.packageName)
                    .put("state", item.state)
            )
        }
        return array
    }

    private fun decodeTracked(array: JSONArray): List<TrackedCampaign> =
        (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            val id = item.optString("campaign_id")
            if (id.isBlank()) return@mapNotNull null
            TrackedCampaign(
                campaignId = id,
                appName = item.optString("app_name").ifBlank { null },
                packageName = item.optString("package_name").ifBlank { null },
                state = item.optString("state").ifBlank { null }
            )
        }

    private fun decodeRecords(raw: String?): JSONObject =
        runCatching { JSONObject(raw ?: "{}") }.getOrDefault(JSONObject())

    private fun toRecord(item: JSONObject): DailyInstallRecord? {
        val campaignId = item.optString("campaign_id")
        val date = item.optString("date")
        if (campaignId.isBlank() || date.isBlank()) return null
        return DailyInstallRecord(
            campaignId = campaignId,
            date = date,
            installed = item.optBoolean("installed", false),
            synced = item.optBoolean("synced", false),
            checkedAt = item.optLong("checked_at", 0L)
        )
    }
}
