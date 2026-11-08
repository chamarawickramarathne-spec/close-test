using System.Text.Json.Serialization;

namespace TesterLoop.Desktop.Core.Data;

public sealed record WhoAmIDto(
    [property: JsonPropertyName("user_id")] Guid UserId,
    [property: JsonPropertyName("role")] string Role,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("developer_id")] Guid? DeveloperId,
    [property: JsonPropertyName("tester_id")] Guid? TesterId,
    [property: JsonPropertyName("company_name")] string? CompanyName,
    [property: JsonPropertyName("tester_name")] string? TesterName);

public sealed record DeveloperDashboardDto(
    [property: JsonPropertyName("developer")] DeveloperDto Developer,
    [property: JsonPropertyName("campaigns")] List<DeveloperCampaignDto> Campaigns);

public sealed record DeveloperDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("company_name")] string CompanyName,
    [property: JsonPropertyName("contact_email")] string ContactEmail,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record DeveloperCampaignDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("group_email")] string? GroupEmail,
    [property: JsonPropertyName("group_name")] string? GroupName,
    [property: JsonPropertyName("group_state")] string? GroupState,
    [property: JsonPropertyName("group_attached_at")] DateTime? GroupAttachedAt,
    [property: JsonPropertyName("play_opt_in_url")] string PlayOptInUrl,
    [property: JsonPropertyName("required_testers")] int RequiredTesters,
    [property: JsonPropertyName("payment_state")] string PaymentState,
    [property: JsonPropertyName("payment_amount_cents")] int PaymentAmountCents,
    [property: JsonPropertyName("payment_reference")] string? PaymentReference,
    [property: JsonPropertyName("paid_at")] DateTime? PaidAt,
    [property: JsonPropertyName("seats_used")] int SeatsUsed,
    [property: JsonPropertyName("testers_used")] int TestersUsed,
    [property: JsonPropertyName("has_joined_testers")] bool HasJoinedTesters,
    [property: JsonPropertyName("opted_in")] int OptedIn,
    [property: JsonPropertyName("days_banked")] int DaysBanked,
    [property: JsonPropertyName("meets_requirement")] bool MeetsRequirement,
    [property: JsonPropertyName("eligible_on")] DateTime? EligibleOn,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt,
    [property: JsonPropertyName("started_at")] DateTime? StartedAt,
    [property: JsonPropertyName("clock_started_at")] DateTime? ClockStartedAt,
    [property: JsonPropertyName("first_opt_in_at")] DateTime? FirstOptInAt,
    [property: JsonPropertyName("delete_locked")] bool DeleteLocked,
    [property: JsonPropertyName("delete_unlocks_at")] DateTime? DeleteUnlocksAt,
    [property: JsonPropertyName("passed_at")] DateTime? PassedAt,
    [property: JsonPropertyName("seats")] List<DeveloperSeatDto> Seats,
    [property: JsonPropertyName("reports")] List<DeveloperReportDto> Reports);

public sealed record DeveloperSeatDto(
    [property: JsonPropertyName("seat_number")] int SeatNumber,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("joined_at")] DateTime? JoinedAt,
    [property: JsonPropertyName("opted_in_at")] DateTime? OptedInAt,
    [property: JsonPropertyName("tester_name")] string TesterName,
    [property: JsonPropertyName("devices")] List<string> Devices,
    [property: JsonPropertyName("region")] string? Region,
    [property: JsonPropertyName("has_report")] bool HasReport);

public sealed record DeveloperReportDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("body")] string Body,
    [property: JsonPropertyName("severity")] string Severity,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("build_label")] string? BuildLabel,
    [property: JsonPropertyName("device")] string? Device,
    [property: JsonPropertyName("evidence_url")] string? EvidenceUrl,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt,
    [property: JsonPropertyName("tester_name")] string TesterName);

public sealed record TesterDashboardDto(
    [property: JsonPropertyName("tester")] TesterDto Tester,
    [property: JsonPropertyName("mine")] List<TesterCampaignDto> Mine,
    [property: JsonPropertyName("available")] List<TesterAvailableDto> Available,
    [property: JsonPropertyName("reports")] List<TesterReportDto> Reports);

public sealed record TesterDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("devices")] List<string> Devices,
    [property: JsonPropertyName("mobile_device_name")] string? MobileDeviceName,
    [property: JsonPropertyName("mobile_device_seen_at")] DateTime? MobileDeviceSeenAt,
    [property: JsonPropertyName("region")] string? Region,
    [property: JsonPropertyName("reliability")] decimal Reliability);

public sealed record TesterCampaignDto(
    [property: JsonPropertyName("campaign_id")] Guid CampaignId,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("group_email")] string? GroupEmail,
    [property: JsonPropertyName("group_name")] string? GroupName,
    [property: JsonPropertyName("play_opt_in_url")] string PlayOptInUrl,
    [property: JsonPropertyName("seat_number")] int SeatNumber,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("opted_in_at")] DateTime? OptedInAt,
    [property: JsonPropertyName("opt_in_verified_at")] DateTime? OptInVerifiedAt,
    [property: JsonPropertyName("opt_in_verification")] string? OptInVerification,
    [property: JsonPropertyName("days")] int Days,
    [property: JsonPropertyName("clock_started_at")] DateTime? ClockStartedAt,
    [property: JsonPropertyName("confirmed_testers")] int ConfirmedTesters,
    [property: JsonPropertyName("required_testers")] int RequiredTesters);

public sealed record TesterAvailableDto(
    [property: JsonPropertyName("campaign_id")] Guid CampaignId,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("group_email")] string? GroupEmail,
    [property: JsonPropertyName("group_name")] string? GroupName,
    [property: JsonPropertyName("seats_free")] int SeatsFree,
    [property: JsonPropertyName("required_testers")] int RequiredTesters);

public sealed record TesterReportDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("campaign_id")] Guid CampaignId,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("severity")] string Severity,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt,
    [property: JsonPropertyName("usage")] AdminTesterUsageDto? Usage,
    [property: JsonPropertyName("usage_captured_at")] DateTime? UsageCapturedAt);

public sealed record AdminDashboardDto(
    [property: JsonPropertyName("counts")] AdminCountsDto Counts,
    [property: JsonPropertyName("pending")] List<AdminPendingDto> Pending,
    [property: JsonPropertyName("group_setup")] List<AdminGroupSetupDto>? GroupSetup,
    [property: JsonPropertyName("groups")] List<AdminGroupDto> Groups,
    [property: JsonPropertyName("campaigns")] List<AdminCampaignDto> Campaigns,
    [property: JsonPropertyName("audit")] List<AdminAuditDto> Audit,
    [property: JsonPropertyName("developers")] List<AdminDeveloperDto>? Developers,
    [property: JsonPropertyName("testers")] List<AdminTesterDto>? Testers,
    [property: JsonPropertyName("feedback")] List<AdminFeedbackDto>? Feedback,
    [property: JsonPropertyName("profile")] AdminProfileDto? Profile,
    [property: JsonPropertyName("payments")] List<AdminPaymentDto>? Payments,
    [property: JsonPropertyName("packages")] List<PaymentPackageDto>? Packages);

public sealed record PaymentPackageDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("amount_cents")] int AmountCents,
    [property: JsonPropertyName("tester_fee_cents")] int TesterFeeCents,
    [property: JsonPropertyName("is_active")] bool IsActive = true,
    [property: JsonPropertyName("campaigns_used")] int CampaignsUsed = 0,
    [property: JsonPropertyName("created_at")] DateTime? CreatedAt = null,
    [property: JsonPropertyName("updated_at")] DateTime? UpdatedAt = null);

public sealed record AdminCountsDto(
    [property: JsonPropertyName("developers")] int Developers,
    [property: JsonPropertyName("pending")] int Pending,
    [property: JsonPropertyName("active")] int Active,
    [property: JsonPropertyName("testers")] int Testers,
    [property: JsonPropertyName("groups")] int Groups);

public sealed record AdminPendingDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("developer")] string Developer,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminGroupSetupDto(
    [property: JsonPropertyName("campaign_id")] Guid CampaignId,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("developer")] string Developer,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("reserved_group_email")] string ReservedGroupEmail,
    [property: JsonPropertyName("reserved_group_url_name")] string ReservedGroupUrlName,
    [property: JsonPropertyName("reserved_group_display_name")] string ReservedGroupDisplayName,
    [property: JsonPropertyName("group_sequence")] int GroupSequence,
    [property: JsonPropertyName("group_identity_reserved_at")] DateTime GroupIdentityReservedAt,
    [property: JsonPropertyName("payment_reference")] string? PaymentReference,
    [property: JsonPropertyName("paid_at")] DateTime? PaidAt,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminGroupDto(
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("name")] string? Name,
    [property: JsonPropertyName("display_name")] string? DisplayName,
    [property: JsonPropertyName("developer")] string Developer,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("provisioned_at")] DateTime? ProvisionedAt,
    [property: JsonPropertyName("settings_confirmed_at")] DateTime? SettingsConfirmedAt,
    [property: JsonPropertyName("members")] int? Members);

public sealed record AdminCampaignDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("developer")] string Developer,
    [property: JsonPropertyName("package_name")] string? PackageName,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("required_testers")] int RequiredTesters,
    [property: JsonPropertyName("payment_state")] string PaymentState,
    [property: JsonPropertyName("payment_amount_cents")] int PaymentAmountCents,
    [property: JsonPropertyName("payment_reference")] string? PaymentReference,
    [property: JsonPropertyName("paid_at")] DateTime? PaidAt,
    [property: JsonPropertyName("seats_used")] int SeatsUsed,
    [property: JsonPropertyName("testers_used")] int TestersUsed,
    [property: JsonPropertyName("opted_in")] int OptedIn);

public sealed record AdminPaymentDto(
    [property: JsonPropertyName("campaign_id")] Guid CampaignId,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("developer")] string Developer,
    [property: JsonPropertyName("package_name")] string PackageName,
    [property: JsonPropertyName("amount_cents")] int AmountCents,
    [property: JsonPropertyName("group_email")] string? GroupEmail,
    [property: JsonPropertyName("group_name")] string? GroupName,
    [property: JsonPropertyName("group_attached_at")] DateTime? GroupAttachedAt,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminAuditDto(
    [property: JsonPropertyName("created_at")] DateTime CreatedAt,
    [property: JsonPropertyName("actor_label")] string ActorLabel,
    [property: JsonPropertyName("action")] string Action,
    [property: JsonPropertyName("target")] string? Target);

public sealed record AdminDeveloperDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("company_name")] string CompanyName,
    [property: JsonPropertyName("contact_email")] string ContactEmail,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("campaign_count")] int CampaignCount,
    [property: JsonPropertyName("live_count")] int LiveCount,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminTesterDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("email")] string? Email,
    [property: JsonPropertyName("google_email")] string GoogleEmail,
    [property: JsonPropertyName("region")] string? Region,
    [property: JsonPropertyName("reliability")] decimal Reliability,
    [property: JsonPropertyName("is_active")] bool IsActive,
    [property: JsonPropertyName("joined_count")] int JoinedCount,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminFeedbackDto(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("app_name")] string AppName,
    [property: JsonPropertyName("developer")] string Developer,
    [property: JsonPropertyName("tester")] string Tester,
    [property: JsonPropertyName("severity")] string Severity,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("created_at")] DateTime CreatedAt);

public sealed record AdminProfileDto(
    [property: JsonPropertyName("display_name")] string DisplayName,
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("note")] string? Note);

public sealed record JoinResultDto(
    [property: JsonPropertyName("campaign_id")] Guid CampaignId,
    [property: JsonPropertyName("seat_number")] int SeatNumber,
    [property: JsonPropertyName("state")] string State,
    [property: JsonPropertyName("play_opt_in_url")] string PlayOptInUrl,
    [property: JsonPropertyName("app_name")] string AppName);
