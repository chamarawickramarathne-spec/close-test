using System.Collections.ObjectModel;

namespace TesterLoop.Admin.ViewModels;

public sealed class AdminTesterDetail
{
    public required string Name { get; init; }

    public required string Email { get; init; }

    public required string Google { get; init; }

    public required string Region { get; init; }

    public required string Devices { get; init; }

    public required string Status { get; init; }

    public required string Created { get; init; }

    public required string ProjectsLabel { get; init; }

    public required string ReportsLabel { get; init; }

    public required string EligibleLabel { get; init; }

    public required string DueLabel { get; init; }

    public required string PaidLabel { get; init; }

    public required bool UsageAvailable { get; init; }

    public required ObservableCollection<AdminTesterCampaignRow> Campaigns { get; init; }

    public bool HasCampaigns => Campaigns.Count > 0;

    public bool HasUsageNotice => !UsageAvailable;

    public string UsageNotice => UsageAvailable
        ? string.Empty
        : "Tester usage needs a database update. Run sql/migrations/028_admin_usage_visibility.sql in Supabase, then reopen this tester.";
}

public sealed class AdminReportDetail
{
    public required string Title { get; init; }

    public required string SeverityLabel { get; init; }

    public required string SeverityTone { get; init; }

    public required string StatusLabel { get; init; }

    public required string StatusTone { get; init; }

    public required string Age { get; init; }

    public required string Filed { get; init; }

    public required string Updated { get; init; }

    public required string ReportId { get; init; }

    public required string TesterName { get; init; }

    public required string TesterEmail { get; init; }

    public required string TesterGoogle { get; init; }

    public required string TesterRegion { get; init; }

    public required string TesterDevices { get; init; }

    public required string TesterMobile { get; init; }

    public required string AppName { get; init; }

    public required string Developer { get; init; }

    public required string Package { get; init; }

    public required string CampaignState { get; init; }

    public required string CampaignStateTone { get; init; }

    public required string Body { get; init; }

    public required string Build { get; init; }

    public required string Device { get; init; }

    public required string Evidence { get; init; }

    public required bool HasEvidence { get; init; }

    public required string SnapshotState { get; init; }

    public required string SnapshotTone { get; init; }

    public required string SnapshotDays { get; init; }

    public required string SnapshotDetail { get; init; }

    public required string SnapshotCaptured { get; init; }

    public required string CurrentState { get; init; }

    public required string CurrentTone { get; init; }

    public required string CurrentDays { get; init; }

    public required string CurrentDetail { get; init; }

    public required string CurrentCaptured { get; init; }

    public required string UsageComparison { get; init; }

    public required string UsageComparisonTone { get; init; }

    public required string InstallHistoryState { get; init; }

    public required string InstallHistoryTone { get; init; }

    public required string InstallHistorySummary { get; init; }

    public required string InstallHistoryWindow { get; init; }

    public required string PackageWarning { get; init; }

    public bool HasPackageWarning => PackageWarning.Length > 0;
}

public sealed class AdminDeveloperDetail
{    public required string Company { get; init; }

    public required string DisplayName { get; init; }

    public required string Contact { get; init; }

    public required string Google { get; init; }

    public required string Created { get; init; }

    public required string ProjectsLabel { get; init; }

    public required string TestersLabel { get; init; }

    public required string FeesPaidLabel { get; init; }

    public required string FeesDueLabel { get; init; }

    public required string PayoutsPaidLabel { get; init; }

    public required string PayoutsDueLabel { get; init; }

    public required ObservableCollection<AdminDeveloperCampaignRow> Campaigns { get; init; }

    public required ObservableCollection<AdminDeveloperGroupRow> Groups { get; init; }

    public required ObservableCollection<AdminDeveloperTesterRow> Testers { get; init; }

    public required ObservableCollection<AuditRow> Audit { get; init; }

    public bool HasCampaigns => Campaigns.Count > 0;

    public bool HasGroups => Groups.Count > 0;

    public bool HasTesters => Testers.Count > 0;

    public bool HasAudit => Audit.Count > 0;
}

public sealed class AdminCampaignDetail
{
    public required string AppName { get; init; }

    public required string Package { get; init; }

    public required string Developer { get; init; }

    public required string DeveloperContact { get; init; }

    public required string DeveloperGoogle { get; init; }

    public required string StateLabel { get; init; }

    public required string StateTone { get; init; }

    public required string Created { get; init; }

    public required string FirstOptIn { get; init; }

    public required string Started { get; init; }

    public required string EligibleOn { get; init; }

    public required string GroupEmail { get; init; }

    public required string GroupName { get; init; }

    public required string GroupDisplayName { get; init; }

    public required string GroupStateLabel { get; init; }

    public required string GroupSettings { get; init; }

    public required string PlayLink { get; init; }

    public required bool HasPlayLink { get; init; }

    public required string PaymentLabel { get; init; }

    public required string PaymentTone { get; init; }

    public required string PaymentReference { get; init; }

    public required string PaymentMethod { get; init; }

    public required string PaidAt { get; init; }

    public required string FeeLabel { get; init; }

    public required string TestersLabel { get; init; }

    public required string SeatsLabel { get; init; }

    public required string OptedLabel { get; init; }

    public required string ReportsLabel { get; init; }

    public required string UsageLabel { get; init; }

    public required string PayoutDueLabel { get; init; }

    public required string PayoutPaidLabel { get; init; }

    public required bool UsageAvailable { get; init; }

    public required ObservableCollection<AdminCampaignTesterRow> Testers { get; init; }

    public required ObservableCollection<AdminCampaignReportRow> Reports { get; init; }

    public required ObservableCollection<AuditRow> Audit { get; init; }

    public bool HasTesters => Testers.Count > 0;

    public bool HasReports => Reports.Count > 0;

    public bool HasAudit => Audit.Count > 0;

    public bool HasUsageNotice => !UsageAvailable;

    public string UsageNotice => UsageAvailable
        ? string.Empty
        : "Project usage needs a database update. Run sql/migrations/019_tester_app_usage.sql in Supabase, then reopen this project.";
}
