using System.Collections.ObjectModel;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private AdminTesterProjectActivity? _testerProject;
    private AdminTesterCampaignRow? _activeTesterProjectRow;

    public AsyncRelayCommand<AdminTesterCampaignRow> OpenTesterProjectCommand { get; private set; } = null!;

    public AsyncRelayCommand<AdminCampaignReportRow> OpenTesterProjectReportCommand { get; private set; } = null!;

    public AsyncRelayCommand RefreshTesterProjectCommand { get; private set; } = null!;

    public RelayCommand BackToTesterActivityCommand { get; private set; } = null!;

    public AdminTesterProjectActivity? TesterProject
    {
        get => _testerProject;
        private set => Set(ref _testerProject, value);
    }

    private async Task OpenTesterProjectAsync(AdminTesterCampaignRow row)
    {
        Error = string.Empty;
        Toast = string.Empty;

        try
        {
            var detail = await _service.GetAdminCampaignDetailAsync(row.CampaignId);
            TesterProject = MapTesterProject(detail, row);
            _activeTesterProjectRow = row;
            TesterPageIndex = 2;
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
            TesterPageIndex = 1;
        }
    }

    private Task RefreshTesterProjectAsync()
        => _activeTesterProjectRow is null
            ? Task.CompletedTask
            : OpenTesterProjectAsync(_activeTesterProjectRow);

    private void BackToTesterActivity()
    {
        TesterPageIndex = 1;
        TesterProject = null;
        _activeTesterProjectRow = null;
    }

    private Task OpenTesterProjectReportAsync(AdminCampaignReportRow row)
        => OpenReportAsync(row.Id, ReportOrigin.TesterProject);

    private static AdminTesterProjectActivity MapTesterProject(
        AdminCampaignDetailDto dto,
        AdminTesterCampaignRow row)
    {
        var campaign = dto.Campaign;
        var seat = dto.Testers?.FirstOrDefault(tester => tester.TesterId == row.TesterId);
        var usage = BuildUsageLabels(seat?.Usage, dto.UsageAvailable);
        var reports = new ObservableCollection<AdminCampaignReportRow>(
            (dto.Reports ?? [])
                .Where(report => report.TesterId == row.TesterId)
                .Select(MapCampaignReport));

        var paid = seat?.PayoutState == "paid" || row.PayoutState == "paid";
        var eligible = seat is null
            ? row.Eligible
            : campaign.State == "passed" && seat.ReportCount > 0;
        var payoutLabel = paid ? "Paid" : eligible ? "Pending" : "Not eligible";
        var payoutTone = paid ? "good" : eligible ? "warn" : "muted";
        var seatState = seat?.State ?? "dropped";
        var seatTone = seatState switch
        {
            "opted_in" => "good",
            "joined" => "warn",
            _ => "muted",
        };

        var optIn = seat?.OptInVerifiedAt is not null
            ? $"Verified {seat.OptInVerifiedAt:yyyy-MM-dd HH:mm}"
            : seat?.OptedInAt is not null
                ? $"Opted {seat.OptedInAt:yyyy-MM-dd HH:mm}"
                : "Not opted in";
        var dropped = seat is null
            ? "Not on roster"
            : seat.DroppedAt is null
                ? "Still on the project"
                : $"Dropped {seat.DroppedAt:yyyy-MM-dd HH:mm}";
        var lastReport = seat?.LastReportAt is null
            ? "No report filed"
            : seat.LastReportAt.Value.ToString("yyyy-MM-dd HH:mm");

        return new AdminTesterProjectActivity
        {
            AppName = campaign.AppName,
            Package = string.IsNullOrWhiteSpace(campaign.PackageName) ? "-" : campaign.PackageName,
            Developer = string.IsNullOrWhiteSpace(campaign.Developer) ? "Unknown developer" : campaign.Developer,
            CampaignStateLabel = StateLabel(campaign.State),
            CampaignStateTone = Tone(campaign.State),
            SeatLabel = seat is null ? row.SeatLabel : $"Seat {seat.SeatNumber}",
            SeatStateLabel = seat is null ? "Not on roster" : SeatLabel(seat.State),
            SeatStateTone = seatTone,
            Joined = seat?.JoinedAt is null ? "Not recorded" : seat.JoinedAt.Value.ToString("yyyy-MM-dd HH:mm"),
            OptIn = optIn,
            Dropped = dropped,
            LastReport = lastReport,
            ReportsLabel = reports.Count == 1 ? "1 report" : $"{reports.Count} reports",
            FirstOptIn = Date(campaign.FirstOptInAt),
            ClockStarted = Date(campaign.ClockStartedAt),
            EligibleOn = Date(campaign.EligibleOn),
            FeeLabel = Money(campaign.TesterPayoutCents),
            PayoutLabel = payoutLabel,
            PayoutTone = payoutTone,
            Reference = string.IsNullOrWhiteSpace(seat?.PayoutReference)
                ? row.Reference
                : seat.PayoutReference,
            PaidLabel = seat?.PaidAt is null
                ? row.PaidLabel
                : seat.PaidAt.Value.ToString("yyyy-MM-dd"),
            UsageStateLabel = usage.State,
            UsageDaysLabel = usage.Days,
            UsageDetail = usage.Detail,
            UsageTone = usage.Tone,
            UsageTooltip = usage.Tooltip,
            UsageAvailable = dto.UsageAvailable,
            Reports = reports,
        };
    }
}
