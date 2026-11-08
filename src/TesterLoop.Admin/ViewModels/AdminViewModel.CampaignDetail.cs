using System.Collections.ObjectModel;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private AdminCampaignDetail? _campaignDetail;
    private AdminCampaignRow? _selectedCampaignRow;
    private int _campaignPageIndex;
    private Guid _campaignDetailId;

    public RelayCommand BackToCampaignsCommand { get; private set; } = null!;

    public AsyncRelayCommand RefreshCampaignCommand { get; private set; } = null!;

    public AdminCampaignDetail? CampaignDetail
    {
        get => _campaignDetail;
        private set => Set(ref _campaignDetail, value);
    }

    public int CampaignPageIndex
    {
        get => _campaignPageIndex;
        set => Set(ref _campaignPageIndex, value);
    }

    public AdminCampaignRow? SelectedCampaignRow
    {
        get => _selectedCampaignRow;
        set
        {
            if (Set(ref _selectedCampaignRow, value) && value is not null && _campaignPageIndex == 0)
            {
                _ = OpenCampaignAsync(value.Id);
            }
        }
    }

    public async Task OpenCampaignAsync(Guid campaignId)
    {
        Error = string.Empty;

        try
        {
            var detail = await _service.GetAdminCampaignDetailAsync(campaignId);
            _campaignDetailId = campaignId;
            CampaignDetail = MapCampaignDetail(detail);
            CampaignPageIndex = 1;
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
            CampaignPageIndex = 0;
            _selectedCampaignRow = null;
            Raise(nameof(SelectedCampaignRow));
        }
    }

    private void BackToCampaigns()
    {
        CampaignPageIndex = 0;
        _selectedCampaignRow = null;
        Raise(nameof(SelectedCampaignRow));
        CampaignDetail = null;
    }

    private Task RefreshCampaignAsync()
        => _campaignDetailId == Guid.Empty ? Task.CompletedTask : OpenCampaignAsync(_campaignDetailId);

    private static AdminCampaignDetail MapCampaignDetail(AdminCampaignDetailDto dto)
    {
        var campaign = dto.Campaign;
        var totals = dto.Totals;
        var passed = campaign.State == "passed";

        var testers = new ObservableCollection<AdminCampaignTesterRow>();
        foreach (var row in dto.Testers ?? [])
        {
            var usage = BuildUsageLabels(row.Usage, dto.UsageAvailable);
            var eligible = passed && row.ReportCount > 0;
            var paid = row.PayoutState == "paid";
            var payoutLabel = paid ? "Paid" : eligible ? "Pending" : "Not eligible";
            var payoutTone = paid ? "good" : eligible ? "warn" : "muted";
            var stateTone = row.State switch
            {
                "opted_in" => "good",
                "joined" => "warn",
                _ => "muted",
            };

            testers.Add(new AdminCampaignTesterRow(
                row.TesterId,
                row.DisplayName,
                row.GoogleEmail,
                string.IsNullOrWhiteSpace(row.Region) ? "No region" : row.Region,
                $"Seat {row.SeatNumber}",
                SeatLabel(row.State),
                stateTone,
                row.OptInVerifiedAt is not null
                    ? $"Verified {row.OptInVerifiedAt:yyyy-MM-dd}"
                    : row.OptedInAt is not null
                        ? $"Opted {row.OptedInAt:yyyy-MM-dd}"
                        : "Not opted in",
                usage.State,
                usage.Tone,
                usage.Days,
                usage.Tooltip,
                row.ReportCount == 1 ? "1 report" : $"{row.ReportCount} reports",
                payoutLabel,
                payoutTone,
                string.IsNullOrWhiteSpace(row.PayoutReference) ? "-" : row.PayoutReference,
                row.PaidAt is null ? "-" : row.PaidAt.Value.ToString("yyyy-MM-dd")));
        }

        var reports = new ObservableCollection<AdminCampaignReportRow>();
        foreach (var row in dto.Reports ?? [])
        {
            var usage = row.UsageSnapshot is null
                ? null
                : BuildUsageLabels(row.UsageSnapshot, true);
            var detail = string.Join(
                " - ",
                new[] { row.BuildLabel, row.Device }
                    .Where(value => !string.IsNullOrWhiteSpace(value)));

            reports.Add(new AdminCampaignReportRow(
                row.Id,
                row.Title,
                row.TesterName,
                Label(row.Severity),
                SeverityTone(row.Severity),
                Label(row.Status),
                StatusTone(row.Status),
                row.CreatedAt.ToString("yyyy-MM-dd HH:mm"),
                detail.Length == 0 ? "No device or build" : detail,
                Preview(row.Body),
                row.Body,
                string.IsNullOrWhiteSpace(row.EvidenceUrl) ? "No evidence" : row.EvidenceUrl,
                !string.IsNullOrWhiteSpace(row.EvidenceUrl),
                usage is null ? "Usage not captured" : $"{usage.State} - {usage.Days}",
                usage?.Tone ?? "muted"));
        }

        var audit = new ObservableCollection<AuditRow>();
        foreach (var entry in dto.Audit ?? [])
        {
            audit.Add(new AuditRow(
                entry.CreatedAt,
                Ago(entry.CreatedAt),
                entry.ActorLabel,
                entry.Action,
                string.IsNullOrWhiteSpace(entry.Target) ? "-" : entry.Target));
        }

        return new AdminCampaignDetail
        {
            AppName = campaign.AppName,
            Package = string.IsNullOrWhiteSpace(campaign.PackageName) ? "-" : campaign.PackageName,
            Developer = campaign.Developer,
            DeveloperContact = string.IsNullOrWhiteSpace(campaign.DeveloperContact) ? "-" : campaign.DeveloperContact,
            DeveloperGoogle = string.IsNullOrWhiteSpace(campaign.DeveloperGoogle) ? "-" : campaign.DeveloperGoogle,
            StateLabel = StateLabel(campaign.State),
            StateTone = Tone(campaign.State),
            Created = campaign.CreatedAt.ToString("yyyy-MM-dd"),
            FirstOptIn = Date(campaign.FirstOptInAt),
            Started = Date(campaign.ClockStartedAt),
            EligibleOn = Date(campaign.EligibleOn),
            GroupEmail = string.IsNullOrWhiteSpace(campaign.GroupEmail) ? "No group attached" : campaign.GroupEmail,
            GroupName = string.IsNullOrWhiteSpace(campaign.GroupName) ? "-" : campaign.GroupName,
            GroupDisplayName = string.IsNullOrWhiteSpace(campaign.GroupDisplayName) ? "-" : campaign.GroupDisplayName,
            GroupStateLabel = GroupLabel(campaign.GroupState ?? "manual"),
            GroupSettings = campaign.GroupSettingsConfirmedAt is null
                ? "Not recorded"
                : campaign.GroupSettingsConfirmedAt.Value.ToString("yyyy-MM-dd"),
            PlayLink = string.IsNullOrWhiteSpace(campaign.PlayOptInUrl) ? "No link saved" : campaign.PlayOptInUrl,
            HasPlayLink = !string.IsNullOrWhiteSpace(campaign.PlayOptInUrl),
            PaymentLabel = PaymentLabel(campaign.PaymentState, campaign.PaymentAmountCents),
            PaymentTone = PaymentTone(campaign.PaymentState),
            PaymentReference = string.IsNullOrWhiteSpace(campaign.PaymentReference) ? "-" : campaign.PaymentReference,
            PaidAt = Date(campaign.PaidAt),
            FeeLabel = $"{Money(campaign.PaymentAmountCents)} fee - {Money(campaign.TesterPayoutCents)} per tester",
            TestersLabel = $"{totals.TestersUsed} / {AppConfig.SeatCap} used",
            SeatsLabel = $"{totals.SeatsUsed} active / {campaign.SeatsFree} free",
            OptedLabel = $"{totals.OptedIn} / {campaign.RequiredTesters} opted in",
            ReportsLabel = $"{totals.Reports} reports - {totals.Reporters} testers - {totals.OpenReports} open",
            UsageLabel = totals.UsageReported == 0
                ? "No usage reported"
                : $"{totals.UsageMet} of {totals.UsageReported} met",
            PayoutDueLabel = Money(totals.PayoutsDueCents),
            PayoutPaidLabel = Money(totals.PayoutsPaidCents),
            UsageAvailable = dto.UsageAvailable,
            Testers = testers,
            Reports = reports,
            Audit = audit,
        };
    }

    private static string Date(DateTime? value)
        => value is null ? "Not yet" : value.Value.ToString("yyyy-MM-dd");

    private static string Preview(string body)
    {
        var text = body.ReplaceLineEndings(" ").Trim();
        return text.Length <= 160 ? text : text[..157] + "...";
    }
}
