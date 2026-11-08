using System.Collections.ObjectModel;

namespace TesterLoop.Admin.ViewModels;

public sealed class AdminTesterProjectActivity
{
    public required string AppName { get; init; }
    public required string Package { get; init; }
    public required string Developer { get; init; }
    public required string CampaignStateLabel { get; init; }
    public required string CampaignStateTone { get; init; }
    public required string SeatLabel { get; init; }
    public required string SeatStateLabel { get; init; }
    public required string SeatStateTone { get; init; }
    public required string Joined { get; init; }
    public required string OptIn { get; init; }
    public required string Dropped { get; init; }
    public required string LastReport { get; init; }
    public required string ReportsLabel { get; init; }
    public required string FirstOptIn { get; init; }
    public required string ClockStarted { get; init; }
    public required string EligibleOn { get; init; }
    public required string FeeLabel { get; init; }
    public required string PayoutLabel { get; init; }
    public required string PayoutTone { get; init; }
    public required string Reference { get; init; }
    public required string PaidLabel { get; init; }
    public required string UsageStateLabel { get; init; }
    public required string UsageDaysLabel { get; init; }
    public required string UsageDetail { get; init; }
    public required string UsageTone { get; init; }
    public required string UsageTooltip { get; init; }
    public required bool UsageAvailable { get; init; }
    public required ObservableCollection<AdminCampaignReportRow> Reports { get; init; }

    public bool HasUsageNotice => !UsageAvailable;

    public string UsageNotice =>
        "Tester usage needs a database update. Run sql/migrations/028_admin_usage_visibility.sql in Supabase, then reopen this project.";

    public bool HasReports => Reports.Count > 0;
}
