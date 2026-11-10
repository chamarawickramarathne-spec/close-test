package lk.closetester.helper.data.api

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class AuthRequest(
    @Json(name = "email") val email: String,
    @Json(name = "password") val password: String,
    @Json(name = "data") val data: Map<String, String>? = null
)

@JsonClass(generateAdapter = true)
data class SendActivationRequest(
    @Json(name = "email") val email: String
)

@JsonClass(generateAdapter = true)
data class AuthResponse(
    @Json(name = "access_token") val accessToken: String? = null,
    @Json(name = "refresh_token") val refreshToken: String? = null,
    @Json(name = "user") val user: AuthUser? = null
)

@JsonClass(generateAdapter = true)
data class AuthUser(
    @Json(name = "id") val id: String? = null,
    @Json(name = "email") val email: String? = null
)

@JsonClass(generateAdapter = true)
data class TesterDashboard(
    @Json(name = "tester") val tester: Tester? = null,
    @Json(name = "mine") val mine: List<MineItem> = emptyList(),
    @Json(name = "available") val available: List<AvailableItem> = emptyList(),
    @Json(name = "reports") val reports: List<ReportItem> = emptyList()
)

@JsonClass(generateAdapter = true)
data class Tester(
    @Json(name = "id") val id: String,
    @Json(name = "display_name") val displayName: String? = null,
    @Json(name = "google_email") val googleEmail: String? = null,
    @Json(name = "email") val email: String? = null,
    @Json(name = "devices") val devices: List<String> = emptyList(),
    @Json(name = "mobile_device_name") val mobileDeviceName: String? = null,
    @Json(name = "mobile_device_seen_at") val mobileDeviceSeenAt: String? = null,
    @Json(name = "region") val region: String? = null,
    @Json(name = "reliability") val reliability: Double? = null
)

@JsonClass(generateAdapter = true)
data class UsageStatus(
    @Json(name = "installed") val installed: Boolean = false,
    @Json(name = "distinct_days_used") val distinctDaysUsed: Int = 0,
    @Json(name = "continuous_days_used") val continuousDaysUsed: Int = 0,
    @Json(name = "meets_usage_requirement") val meetsUsageRequirement: Boolean = false,
    @Json(name = "last_usage_at") val lastUsageAt: String? = null,
    @Json(name = "first_install_at") val firstInstallAt: String? = null,
    @Json(name = "available") val available: Boolean = true,
    @Json(name = "package_name") val packageName: String? = null,
    @Json(name = "captured_at") val capturedAt: String? = null
)

@JsonClass(generateAdapter = true)
data class MineItem(
    @Json(name = "campaign_id") val campaignId: String,
    @Json(name = "app_name") val appName: String? = null,
    @Json(name = "package_name") val packageName: String? = null,
    @Json(name = "group_email") val groupEmail: String? = null,
    @Json(name = "group_name") val groupName: String? = null,
    @Json(name = "play_opt_in_url") val playOptInUrl: String? = null,
    @Json(name = "seat_number") val seatNumber: Int? = null,
    @Json(name = "state") val state: String? = null,
    @Json(name = "opted_in_at") val optedInAt: String? = null,
    @Json(name = "opt_in_verified_at") val optInVerifiedAt: String? = null,
    @Json(name = "opt_in_verification") val optInVerification: String? = null,
    @Json(name = "days") val days: Int = 0,
    @Json(name = "clock_started_at") val clockStartedAt: String? = null,
    @Json(name = "confirmed_testers") val confirmedTesters: Int? = null,
    @Json(name = "required_testers") val requiredTesters: Int = 12,
    @Json(name = "campaign_state") val campaignState: String? = null,
    @Json(name = "joined_at") val joinedAt: String? = null,
    @Json(name = "usage_status") val usageStatus: UsageStatus? = null
)

@JsonClass(generateAdapter = true)
data class AvailableItem(
    @Json(name = "campaign_id") val campaignId: String,
    @Json(name = "app_name") val appName: String? = null,
    @Json(name = "package_name") val packageName: String? = null,
    @Json(name = "group_email") val groupEmail: String? = null,
    @Json(name = "group_name") val groupName: String? = null,
    @Json(name = "seats_free") val seatsFree: Int = 0,
    @Json(name = "required_testers") val requiredTesters: Int = 12
)

@JsonClass(generateAdapter = true)
data class ReportItem(
    @Json(name = "id") val id: String,
    @Json(name = "campaign_id") val campaignId: String,
    @Json(name = "app_name") val appName: String? = null,
    @Json(name = "severity") val severity: String? = null,
    @Json(name = "status") val status: String? = null,
    @Json(name = "title") val title: String? = null,
    @Json(name = "created_at") val createdAt: String? = null,
    @Json(name = "usage") val usage: UsageStatus? = null,
    @Json(name = "usage_captured_at") val usageCapturedAt: String? = null,
    @Json(name = "install_history") val installHistory: List<DailyInstallItem> = emptyList(),
    @Json(name = "install_history_captured_at") val installHistoryCapturedAt: String? = null,
    @Json(name = "install_window_start") val installWindowStart: String? = null,
    @Json(name = "install_window_end") val installWindowEnd: String? = null
)

@JsonClass(generateAdapter = true)
data class DailyInstallItem(
    @Json(name = "date") val date: String,
    @Json(name = "installed") val installed: Boolean? = null,
    @Json(name = "checked") val checked: Boolean = false,
    @Json(name = "checked_at") val checkedAt: String? = null
)

@JsonClass(generateAdapter = true)
data class SetOptInRequest(
    @Json(name = "p_campaign_id") val campaignId: String,
    @Json(name = "p_opted_in") val optedIn: Boolean
)

@JsonClass(generateAdapter = true)
data class ReportInstallRequest(
    @Json(name = "p_campaign_id") val campaignId: String,
    @Json(name = "p_date") val date: String,
    @Json(name = "p_installed") val installed: Boolean,
    @Json(name = "p_source") val source: String
)

@JsonClass(generateAdapter = true)
data class EnsureRoleRequest(
    @Json(name = "p_role") val role: String
)

@JsonClass(generateAdapter = true)
data class RecordDeviceRequest(
    @Json(name = "p_device_name") val deviceName: String
)

@JsonClass(generateAdapter = true)
data class RpcRequest(
    @Json(name = "p_campaign_id") val pCampaignId: String? = null,
    @Json(name = "p_installed") val pInstalled: Boolean? = null,
    @Json(name = "p_date") val pDate: String? = null,
    @Json(name = "p_foreground_ms") val pForegroundMs: Long? = null,
    @Json(name = "p_sessions") val pSessions: Int? = null
)

@JsonClass(generateAdapter = true)
data class UpdateProfileRequest(
    @Json(name = "p_display_name") val displayName: String,
    @Json(name = "p_google_email") val googleEmail: String,
    @Json(name = "p_region") val region: String? = null,
    @Json(name = "p_devices") val devices: List<String> = emptyList()
)

@JsonClass(generateAdapter = true)
data class FileReportRequest(
    @Json(name = "p_campaign_id") val campaignId: String,
    @Json(name = "p_severity") val severity: String,
    @Json(name = "p_title") val title: String,
    @Json(name = "p_body") val body: String,
    @Json(name = "p_build_label") val buildLabel: String? = null,
    @Json(name = "p_device") val device: String? = null,
    @Json(name = "p_evidence_url") val evidenceUrl: String? = null
)
