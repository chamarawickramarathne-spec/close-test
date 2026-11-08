using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private AdminReportDetail? _reportDetail;
    private FeedbackRow? _selectedFeedbackRow;
    private int _feedbackPageIndex;

    public RelayCommand BackToFeedbackCommand { get; private set; } = null!;

    public RelayCommand CopyReportEvidenceCommand { get; private set; } = null!;

    public AdminReportDetail? ReportDetail
    {
        get => _reportDetail;
        private set => Set(ref _reportDetail, value);
    }

    public int FeedbackPageIndex
    {
        get => _feedbackPageIndex;
        set => Set(ref _feedbackPageIndex, value);
    }

    public FeedbackRow? SelectedFeedbackRow
    {
        get => _selectedFeedbackRow;
        set
        {
            if (Set(ref _selectedFeedbackRow, value) && value is not null && _feedbackPageIndex == 0)
            {
                _ = OpenReportAsync(value.Id);
            }
        }
    }

    public async Task OpenReportAsync(Guid reportId)
    {
        Error = string.Empty;
        Toast = string.Empty;

        try
        {
            var detail = await _service.GetAdminReportDetailAsync(reportId);
            ReportDetail = MapReportDetail(detail);
            FeedbackPageIndex = 1;
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
            FeedbackPageIndex = 0;
            _selectedFeedbackRow = null;
            Raise(nameof(SelectedFeedbackRow));
        }
    }

    private void BackToFeedback()
    {
        FeedbackPageIndex = 0;
        _selectedFeedbackRow = null;
        Raise(nameof(SelectedFeedbackRow));
        ReportDetail = null;
    }

    private void CopyReportEvidence()
    {
        if (ReportDetail is null || !ReportDetail.HasEvidence)
        {
            return;
        }

        CopyText(ReportDetail.Evidence, "Evidence link copied.");
    }

    private static AdminReportDetail MapReportDetail(AdminReportDetailDto dto)
    {
        var report = dto.Report;
        var campaign = dto.Campaign;
        var tester = dto.Tester;
        var snapshot = BuildReportUsage(dto.UsageSnapshot, true);
        var current = BuildReportUsage(dto.CurrentUsage, false);
        var comparison = CompareUsage(dto.UsageSnapshot, dto.CurrentUsage);
        var install = BuildInstallHistory(dto);
        var snapshotPackage = dto.UsageSnapshot?.PackageName;
        var packageWarning = dto.UsageSnapshot is { Available: true }
                             && !string.IsNullOrWhiteSpace(snapshotPackage)
                             && !string.Equals(snapshotPackage, campaign.PackageName, StringComparison.OrdinalIgnoreCase)
            ? $"Usage was recorded for {snapshotPackage}, not {campaign.PackageName}."
            : string.Empty;

        return new AdminReportDetail
        {
            Title = report.Title,
            SeverityLabel = Label(report.Severity),
            SeverityTone = SeverityTone(report.Severity),
            StatusLabel = Label(report.Status),
            StatusTone = StatusTone(report.Status),
            Age = Ago(report.CreatedAt),
            Filed = report.CreatedAt.ToString("yyyy-MM-dd HH:mm"),
            Updated = report.UpdatedAt.ToString("yyyy-MM-dd HH:mm"),
            ReportId = report.Id.ToString("N")[..8].ToUpperInvariant(),
            TesterName = tester.DisplayName,
            TesterEmail = tester.Email ?? "-",
            TesterGoogle = tester.GoogleEmail,
            TesterRegion = string.IsNullOrWhiteSpace(tester.Region) ? "No region" : tester.Region,
            TesterDevices = tester.Devices is null || tester.Devices.Count == 0
                ? "No devices listed"
                : string.Join(", ", tester.Devices),
            TesterMobile = string.IsNullOrWhiteSpace(tester.MobileDeviceName)
                ? "Not reported"
                : tester.MobileDeviceName,
            AppName = campaign.AppName,
            Developer = string.IsNullOrWhiteSpace(campaign.Developer)
                ? "Unknown developer"
                : campaign.Developer,
            Package = campaign.PackageName,
            CampaignState = StateLabel(campaign.State),
            CampaignStateTone = Tone(campaign.State),
            Body = report.Body,
            Build = string.IsNullOrWhiteSpace(report.BuildLabel) ? "Not provided" : report.BuildLabel,
            Device = string.IsNullOrWhiteSpace(report.Device) ? "Not provided" : report.Device,
            Evidence = string.IsNullOrWhiteSpace(report.EvidenceUrl) ? "Not provided" : report.EvidenceUrl,
            HasEvidence = !string.IsNullOrWhiteSpace(report.EvidenceUrl),
            SnapshotState = snapshot.State,
            SnapshotTone = snapshot.Tone,
            SnapshotDays = snapshot.Days,
            SnapshotDetail = snapshot.Detail,
            SnapshotCaptured = dto.UsageCapturedAt is null
                ? "Not recorded"
                : $"Captured {dto.UsageCapturedAt:yyyy-MM-dd HH:mm}",
            CurrentState = current.State,
            CurrentTone = current.Tone,
            CurrentDays = current.Days,
            CurrentDetail = current.Detail,
            CurrentCaptured = "Live now",
            UsageComparison = comparison.Text,
            UsageComparisonTone = comparison.Tone,
            InstallHistoryState = install.State,
            InstallHistoryTone = install.Tone,
            InstallHistorySummary = install.Summary,
            InstallHistoryWindow = install.Footer,
            PackageWarning = packageWarning,
        };
    }

    private static ReportUsageLabels BuildReportUsage(
        AdminTesterUsageDto? usage,
        bool snapshot)
    {
        if (usage is null)
        {
            return snapshot
                ? new ReportUsageLabels(
                    "Not captured",
                    "muted",
                    "No snapshot",
                    "This report was filed before usage snapshots were enabled.")
                : new ReportUsageLabels(
                    "Not reported",
                    "muted",
                    "No data",
                    "No install or usage data has been reported for this project.");
        }

        if (!usage.Available)
        {
            return snapshot
                ? new ReportUsageLabels(
                    "Not reported",
                    "muted",
                    "No data",
                    "No install or usage data had been reported when this report was filed.")
                : new ReportUsageLabels(
                    "Not reported",
                    "muted",
                    "No data",
                    "No install or usage data has been reported for this project.");
        }

        var state = usage.MeetsUsageRequirement
            ? "Met"
            : usage.Installed
                ? "In progress"
                : "Not installed";
        var tone = usage.MeetsUsageRequirement
            ? "good"
            : usage.Installed ? "warn" : "muted";
        var days = $"{usage.ContinuousDaysUsed}/{AppConfig.RequiredDays} days";
        var lastUsed = usage.LastUsageAt is null
            ? "no usage yet"
            : $"last used {usage.LastUsageAt:yyyy-MM-dd}";
        var detail = $"Installed: {(usage.Installed ? "yes" : "no")} - "
                     + $"{usage.DistinctDaysUsed} distinct days - {lastUsed}";

        return new ReportUsageLabels(state, tone, days, detail);
    }

    private static (string Text, string Tone) CompareUsage(
        AdminTesterUsageDto? snapshot,
        AdminTesterUsageDto? current)
    {
        if (snapshot is null)
        {
            return ("No usage was captured with this report. Live usage is shown for context.", "muted");
        }

        if (current is null)
        {
            return ("The tester has not reported live usage for this project.", "muted");
        }

        var same = snapshot.Installed == current.Installed
                   && snapshot.DistinctDaysUsed == current.DistinctDaysUsed
                   && snapshot.ContinuousDaysUsed == current.ContinuousDaysUsed
                   && snapshot.MeetsUsageRequirement == current.MeetsUsageRequirement;

        return same
            ? ("Live usage matches the snapshot taken when this report was filed.", "good")
            : ("Live usage has changed since this report was filed.", "warn");
    }

    private sealed record ReportUsageLabels(
        string State,
        string Tone,
        string Days,
        string Detail);

    private static ReportInstallLabels BuildInstallHistory(AdminReportDetailDto dto)
    {
        var history = dto.InstallHistory;
        if (history is null || history.Count == 0)
        {
            return new ReportInstallLabels(
                "Not captured",
                "muted",
                "No daily install checks were stored with this report.",
                "This report predates daily install history.");
        }

        var checkedDays = history.Count(day => day.Checked);
        var installedDays = history.Count(day => day.Checked && day.Installed == true);
        var missingDays = history.Count(day => day.Checked && day.Installed == false);

        var state = checkedDays == 0
            ? "Not checked"
            : missingDays == 0
                ? "Installed daily"
                : installedDays == 0
                    ? "Not installed"
                    : "Gaps found";
        var tone = checkedDays == 0
            ? "muted"
            : missingDays == 0
                ? "good"
                : installedDays == 0
                    ? "bad"
                    : "warn";

        var summary = checkedDays == 0
            ? $"{history.Count} days in window, none checked"
            : $"{installedDays} of {checkedDays} checked days installed";

        var window = dto.InstallWindowStart is null || dto.InstallWindowEnd is null
            ? string.Empty
            : $"Window {dto.InstallWindowStart.Value:yyyy-MM-dd} to {dto.InstallWindowEnd.Value:yyyy-MM-dd}";
        var captured = dto.InstallHistoryCapturedAt is null
            ? "Not captured"
            : $"Captured {dto.InstallHistoryCapturedAt:yyyy-MM-dd HH:mm}";
        var footer = window.Length == 0 ? captured : $"{window} - {captured}";

        return new ReportInstallLabels(state, tone, summary, footer);
    }

    private sealed record ReportInstallLabels(
        string State,
        string Tone,
        string Summary,
        string Footer);
}
