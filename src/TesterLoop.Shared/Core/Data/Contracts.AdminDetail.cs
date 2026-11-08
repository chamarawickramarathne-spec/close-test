using System.Text.Json.Serialization;

namespace TesterLoop.Desktop.Core.Data;

public sealed record AdminTesterDetailDto(
    [property: JsonPropertyName("usage_available")] bool UsageAvailable,
    [property: JsonPropertyName("tester")] AdminTesterProfileDto Tester,
    [property: JsonPropertyName("totals")] AdminTesterTotalsDto Totals,
    [property: JsonPropertyName("campaigns")] List<AdminTesterCampaignDto> Campaigns);

public sealed record AdminTesterProfileDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("email")] string? Email,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("region")] string? Region,
    [property: JsonPropertyName("devices")] List<string>? Devices,
    [property: JsonPropertyName("reliability")] decimal Reliability,
    [property: JsonPropertyName("is_active")] bool IsActive,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminTesterTotalsDto(
    [property: JsonPropertyName("projects")] int Projects,
    [property: JsonPropertyName("active_seats")] int ActiveSeats,
    [property: JsonPropertyName("reports")] int Reports,
    [property: JsonPropertyName("eligible_count")] int EligibleCount,
    [property: JsonPropertyName("eligible_cents")] int EligibleCents,
    [property: JsonPropertyName("due_cents")] int DueCents,
    [property: JsonPropertyName("paid_cents")] int PaidCents);

public sealed record AdminTesterCampaignDto(
    [property: JsonPropertyName("seat_id")] Guid SeatId,
    [property: JsonPropertyName("campaign_id")] Guid CampaignId,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("developer")] string Developer,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("campaign_state")] string CampaignState,
    [property: JsonPropertyName("seat_state")] string SeatState,
    [property: JsonPropertyName("seat_number")] int SeatNumber,
    [property: JsonPropertyName("joined_at")] DateTime? JoinedAt,
    [property: JsonPropertyName("opted_in_at")] DateTime? OptedInAt,
    [property: JsonPropertyName("opt_in_verified_at")] DateTime? OptInVerifiedAt,
    [property: JsonPropertyName("report_count")] int ReportCount,
    [property: JsonPropertyName("last_report_at")] DateTime? LastReportAt,
    [property: JsonPropertyName("fee_cents")] int FeeCents,
    [property: JsonPropertyName("eligible")] bool Eligible,
    [property: JsonPropertyName("payout_state")] string PayoutState,
    [property: JsonPropertyName("payout_reference")] string? PayoutReference,
    [property: JsonPropertyName("paid_at")] DateTime? PaidAt,
    [property: JsonPropertyName("usage")] AdminTesterUsageDto? Usage);

public sealed record AdminTesterUsageDto(
    [property: JsonPropertyName("installed")] bool Installed,
    [property: JsonPropertyName("distinct_days_used")] int DistinctDaysUsed,
    [property: JsonPropertyName("continuous_days_used")] int ContinuousDaysUsed,
    [property: JsonPropertyName("meets_usage_requirement")] bool MeetsUsageRequirement,
    [property: JsonPropertyName("last_usage_at")] DateTime? LastUsageAt,
    [property: JsonPropertyName("first_install_at")] DateTime? FirstInstallAt,
    [property: JsonPropertyName("available")] bool Available = true,
    [property: JsonPropertyName("package_name")] string? PackageName = null);

public sealed record AdminInstallCheckDto(
    [property: JsonPropertyName("date")] DateOnly Date,
    [property: JsonPropertyName("installed")] bool? Installed,
    [property: JsonPropertyName("checked")] bool Checked,
    [property: JsonPropertyName("checked_at")] DateTime? CheckedAt);

public sealed record AdminDeveloperDetailDto(
    [property: JsonPropertyName("developer")] AdminDeveloperProfileDto Developer,
    [property: JsonPropertyName("totals")] AdminDeveloperTotalsDto Totals,
    [property: JsonPropertyName("campaigns")] List<AdminDeveloperCampaignDto> Campaigns,
    [property: JsonPropertyName("groups")] List<AdminDeveloperGroupDto> Groups,
    [property: JsonPropertyName("testers")] List<AdminDeveloperTesterDto> Testers,
    [property: JsonPropertyName("audit")] List<AdminAuditDto> Audit);

public sealed record AdminDeveloperProfileDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("company_name")] string CompanyName,
    [property: JsonPropertyName("contact_email")] string ContactEmail,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("display_name")] string? DisplayName,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminDeveloperTotalsDto(
    [property: JsonPropertyName("projects")] int Projects,
    [property: JsonPropertyName("live")] int Live,
    [property: JsonPropertyName("passed")] int Passed,
    [property: JsonPropertyName("testers_used")] int TestersUsed,
    [property: JsonPropertyName("active_seats")] int ActiveSeats,
    [property: JsonPropertyName("reports")] int Reports,
    [property: JsonPropertyName("project_fees_paid_cents")] int ProjectFeesPaidCents,
    [property: JsonPropertyName("project_fees_due_cents")] int ProjectFeesDueCents,
    [property: JsonPropertyName("tester_payouts_paid_cents")] int TesterPayoutsPaidCents,
    [property: JsonPropertyName("tester_payouts_due_cents")] int TesterPayoutsDueCents);

public sealed record AdminDeveloperCampaignDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("payment_state")] string PaymentState,
    [property: JsonPropertyName("payment_amount_cents")] int PaymentAmountCents,
    [property: JsonPropertyName("payment_reference")] string? PaymentReference,
    [property: JsonPropertyName("paid_at")] DateTime? PaidAt,
    [property: JsonPropertyName("seats_used")] int SeatsUsed,
    [property: JsonPropertyName("testers_used")] int TestersUsed,
    [property: JsonPropertyName("opted_in")] int OptedIn,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminDeveloperGroupDto(
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("provisioned_at")] DateTime? ProvisionedAt,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminDeveloperTesterDto(
    [property: JsonPropertyName("tester_id")] Guid TesterId,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("campaigns")] int Campaigns,
    [property: JsonPropertyName("active_seats")] int ActiveSeats,
    [property: JsonPropertyName("reports")] int Reports,
    [property: JsonPropertyName("due_cents")] int DueCents,
    [property: JsonPropertyName("paid_cents")] int PaidCents);

public sealed record AdminReportDetailDto(
    [property: JsonPropertyName("report")] AdminReportDto Report,
    [property: JsonPropertyName("campaign")] AdminReportCampaignDto Campaign,
    [property: JsonPropertyName("tester")] AdminReportTesterDto Tester,
    [property: JsonPropertyName("usage_snapshot")] AdminTesterUsageDto? UsageSnapshot,
    [property: JsonPropertyName("usage_captured_at")] DateTime? UsageCapturedAt,
    [property: JsonPropertyName("current_usage")] AdminTesterUsageDto? CurrentUsage,
    [property: JsonPropertyName("install_history")] IReadOnlyList<AdminInstallCheckDto>? InstallHistory,
    [property: JsonPropertyName("install_history_captured_at")] DateTime? InstallHistoryCapturedAt,
    [property: JsonPropertyName("install_window_start")] DateOnly? InstallWindowStart,
    [property: JsonPropertyName("install_window_end")] DateOnly? InstallWindowEnd);

public sealed record AdminReportDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("severity")] string Severity,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("body")] string Body,
    [property: JsonPropertyName("build_label")] string? BuildLabel,
    [property: JsonPropertyName("device")] string? Device,
    [property: JsonPropertyName("evidence_url")] string? EvidenceUrl,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt,
    [property: JsonPropertyName("updated_at")] DateTime UpdatedAt);

public sealed record AdminReportCampaignDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("developer")] string? Developer);

public sealed record AdminReportTesterDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("email")] string? Email,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("region")] string? Region,
    [property: JsonPropertyName("devices")] List<string>? Devices,
    [property: JsonPropertyName("mobile_device_name")] string? MobileDeviceName);

public sealed record AdminCampaignDetailDto(
    [property: JsonPropertyName("usage_available")] bool UsageAvailable,
    [property: JsonPropertyName("campaign")] AdminCampaignProfileDto Campaign,
    [property: JsonPropertyName("totals")] AdminCampaignTotalsDto Totals,
    [property: JsonPropertyName("testers")] List<AdminCampaignTesterDto> Testers,
    [property: JsonPropertyName("reports")] List<AdminCampaignReportDto> Reports,
    [property: JsonPropertyName("audit")] List<AdminAuditDto> Audit);

public sealed record AdminCampaignProfileDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("developer")] string Developer,
    [property: JsonPropertyName("developer_contact")] string? DeveloperContact,
    [property: JsonPropertyName("developer_google")] string? DeveloperGoogle,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("play_opt_in_url")] string? PlayOptInUrl,
    [property: JsonPropertyName("required_testers")] int RequiredTesters,
    [property: JsonPropertyName("payment_package")] string? PaymentPackage,
    [property: JsonPropertyName("payment_state")] string PaymentState,
    [property: JsonPropertyName("payment_amount_cents")] int PaymentAmountCents,
    [property: JsonPropertyName("tester_payout_cents")] int TesterPayoutCents,
    [property: JsonPropertyName("payment_reference")] string? PaymentReference,
    [property: JsonPropertyName("paid_at")] DateTime? PaidAt,
    [property: JsonPropertyName("group_email")] string? GroupEmail,
    [property: JsonPropertyName("group_name")] string? GroupName,
    [property: JsonPropertyName("group_display_name")] string? GroupDisplayName,
    [property: JsonPropertyName("group_state")] string? GroupState,
    [property: JsonPropertyName("group_provisioned_at")] DateTime? GroupProvisionedAt,
    [property: JsonPropertyName("group_settings_confirmed_at")] DateTime? GroupSettingsConfirmedAt,
    [property: JsonPropertyName("seats_used")] int SeatsUsed,
    [property: JsonPropertyName("seats_free")] int SeatsFree,
    [property: JsonPropertyName("testers_used")] int TestersUsed,
    [property: JsonPropertyName("opted_in")] int OptedIn,
    [property: JsonPropertyName("days_banked")] int DaysBanked,
    [property: JsonPropertyName("meets_requirement")] bool MeetsRequirement,
    [property: JsonPropertyName("eligible_on")] DateTime? EligibleOn,
    [property: JsonPropertyName("clock_started_at")] DateTime? ClockStartedAt,
    [property: JsonPropertyName("first_opt_in_at")] DateTime? FirstOptInAt,
    [property: JsonPropertyName("started_at")] DateTime? StartedAt,
    [property: JsonPropertyName("passed_at")] DateTime? PassedAt,
    [property: JsonPropertyName("cancelled_at")] DateTime? CancelledAt,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminCampaignTotalsDto(
    [property: JsonPropertyName("testers_used")] int TestersUsed,
    [property: JsonPropertyName("seats_used")] int SeatsUsed,
    [property: JsonPropertyName("joined")] int Joined,
    [property: JsonPropertyName("opted_in")] int OptedIn,
    [property: JsonPropertyName("verified_opt_in")] int VerifiedOptIn,
    [property: JsonPropertyName("dropped")] int Dropped,
    [property: JsonPropertyName("reports")] int Reports,
    [property: JsonPropertyName("reporters")] int Reporters,
    [property: JsonPropertyName("open_reports")] int OpenReports,
    [property: JsonPropertyName("usage_reported")] int UsageReported,
    [property: JsonPropertyName("usage_met")] int UsageMet,
    [property: JsonPropertyName("payouts_eligible_cents")] int PayoutsEligibleCents,
    [property: JsonPropertyName("payouts_due_cents")] int PayoutsDueCents,
    [property: JsonPropertyName("payouts_paid_cents")] int PayoutsPaidCents);

public sealed record AdminCampaignTesterDto(
    [property: JsonPropertyName("tester_id")] Guid TesterId,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("region")] string? Region,
    [property: JsonPropertyName("seat_number")] int SeatNumber,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("joined_at")] DateTime? JoinedAt,
    [property: JsonPropertyName("opted_in_at")] DateTime? OptedInAt,
    [property: JsonPropertyName("opt_in_verified_at")] DateTime? OptInVerifiedAt,
    [property: JsonPropertyName("dropped_at")] DateTime? DroppedAt,
    [property: JsonPropertyName("report_count")] int ReportCount,
    [property: JsonPropertyName("last_report_at")] DateTime? LastReportAt,
    [property: JsonPropertyName("payout_amount_cents")] int PayoutAmountCents,
    [property: JsonPropertyName("payout_state")] string PayoutState,
    [property: JsonPropertyName("payout_reference")] string? PayoutReference,
    [property: JsonPropertyName("paid_at")] DateTime? PaidAt,
    [property: JsonPropertyName("usage")] AdminTesterUsageDto? Usage);

public sealed record AdminCampaignReportDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("tester_id")] Guid TesterId,
    [property: JsonPropertyName("tester_name")] string TesterName,
    [property: JsonPropertyName("severity")] string Severity,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("body")] string Body,
    [property: JsonPropertyName("build_label")] string? BuildLabel,
    [property: JsonPropertyName("device")] string? Device,
    [property: JsonPropertyName("evidence_url")] string? EvidenceUrl,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt,
    [property: JsonPropertyName("updated_at")] DateTime UpdatedAt,
    [property: JsonPropertyName("usage_snapshot")] AdminTesterUsageDto? UsageSnapshot,
    [property: JsonPropertyName("usage_captured_at")] DateTime? UsageCapturedAt);
