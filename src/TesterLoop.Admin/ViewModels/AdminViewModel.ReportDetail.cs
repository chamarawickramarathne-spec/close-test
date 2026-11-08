using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private AdminReportDetail? _reportDetail;
    private FeedbackRow? _selectedFeedbackRow;
    private int _feedbackPageIndex;
    private ReportOrigin _reportOrigin = ReportOrigin.Feedback;

    public RelayCommand BackFromReportCommand { get; private set; } = null!;

    public RelayCommand CopyReportEvidenceCommand { get; private set; } = null!;

    public string ReportBackLabel => _reportOrigin switch
    {
        ReportOrigin.Campaign => "Back to project",
        ReportOrigin.TesterProject => "Back to activity",
        _ => "Back to feedback",
    };

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
                _ = OpenReportAsync(value.Id, ReportOrigin.Feedback);
            }
        }
    }

    public Task OpenReportAsync(Guid reportId)
        => OpenReportAsync(reportId, ReportOrigin.Feedback);

    private async Task OpenReportAsync(Guid reportId, ReportOrigin origin)
    {
        Error = string.Empty;
        Toast = string.Empty;
        SetReportOrigin(origin);

        try
        {
            var detail = await _service.GetAdminReportDetailAsync(reportId);
            ReportDetail = MapReportDetail(detail);
            NavigateToReportPage(origin);
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
            NavigateBackFromReport(origin);
        }
    }

    private void BackFromReport()
    {
        var origin = _reportOrigin;
        ReportDetail = null;
        NavigateBackFromReport(origin);
    }

    private void SetReportOrigin(ReportOrigin origin)
    {
        _reportOrigin = origin;
        Raise(nameof(ReportBackLabel));
    }

    private void NavigateToReportPage(ReportOrigin origin)
    {
        switch (origin)
        {
            case ReportOrigin.Campaign:
                CampaignPageIndex = 2;
                break;
            case ReportOrigin.TesterProject:
                TesterPageIndex = 3;
                break;
            default:
                FeedbackPageIndex = 1;
                break;
        }
    }

    private void NavigateBackFromReport(ReportOrigin origin)
    {
        switch (origin)
        {
            case ReportOrigin.Campaign:
                CampaignPageIndex = 1;
                break;
            case ReportOrigin.TesterProject:
                TesterPageIndex = 2;
                break;
            default:
                FeedbackPageIndex = 0;
                _selectedFeedbackRow = null;
                Raise(nameof(SelectedFeedbackRow));
                break;
        }
    }

    private enum ReportOrigin
    {
        Feedback,
        Campaign,
        TesterProject,
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

}
