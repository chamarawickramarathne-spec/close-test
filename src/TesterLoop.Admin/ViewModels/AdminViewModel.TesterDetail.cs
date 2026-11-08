using System.Collections.ObjectModel;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private AdminTesterDetail? _testerDetail;
    private TesterRow? _selectedTesterRow;
    private int _testerPageIndex;
    private string _testerPayoutReference = string.Empty;

    public AsyncRelayCommand<AdminTesterCampaignRow> MarkTesterPaidCommand { get; private set; } = null!;

    public RelayCommand BackToTestersCommand { get; private set; } = null!;

    public AdminTesterDetail? TesterDetail
    {
        get => _testerDetail;
        private set => Set(ref _testerDetail, value);
    }

    public int TesterPageIndex
    {
        get => _testerPageIndex;
        set => Set(ref _testerPageIndex, value);
    }

    public TesterRow? SelectedTesterRow
    {
        get => _selectedTesterRow;
        set
        {
            if (Set(ref _selectedTesterRow, value) && value is not null && _testerPageIndex == 0)
            {
                _ = OpenTesterAsync(value.Id);
            }
        }
    }

    public string TesterPayoutReference
    {
        get => _testerPayoutReference;
        set => Set(ref _testerPayoutReference, value);
    }

    public async Task OpenTesterAsync(Guid testerId)
    {
        Error = string.Empty;
        Toast = string.Empty;

        try
        {
            var detail = await _service.GetAdminTesterDetailAsync(testerId);
            TesterPayoutReference = string.Empty;
            TesterDetail = MapTesterDetail(detail);
            TesterPageIndex = 1;
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
            TesterPageIndex = 0;
            _selectedTesterRow = null;
            Raise(nameof(SelectedTesterRow));
        }
    }

    private void BackToTesters()
    {
        TesterPageIndex = 0;
        _selectedTesterRow = null;
        Raise(nameof(SelectedTesterRow));
        TesterDetail = null;
    }

    private async Task MarkTesterPaidAsync(AdminTesterCampaignRow row)
    {
        Error = string.Empty;
        Toast = string.Empty;

        try
        {
            await _service.ConfirmTesterPayoutAsync(
                row.CampaignId,
                row.TesterId,
                TesterPayoutReference);

            TesterPayoutReference = string.Empty;
            await OpenTesterAsync(row.TesterId);
            Toast = $"Payout recorded for {row.AppName}: {row.FeeLabel}.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private static AdminTesterDetail MapTesterDetail(AdminTesterDetailDto dto)
    {
        var campaigns = new ObservableCollection<AdminTesterCampaignRow>();
        foreach (var row in dto.Campaigns ?? [])
        {
            var paid = row.PayoutState == "paid";
            var tone = paid ? "good" : row.Eligible ? "warn" : "muted";
            var payoutLabel = paid ? "Paid" : row.Eligible ? "Eligible" : "Not yet";
            var usage = BuildUsageLabels(row.Usage, dto.UsageAvailable);

            campaigns.Add(new AdminTesterCampaignRow(
                row.SeatId,
                row.CampaignId,
                dto.Tester.Id,
                row.AppName,
                row.Developer,
                StateLabel(row.CampaignState),
                $"{SeatLabel(row.SeatState)} - seat {row.SeatNumber}",
                row.OptInVerifiedAt is null
                    ? "Not verified"
                    : $"Verified {row.OptInVerifiedAt:yyyy-MM-dd HH:mm}",
                row.ReportCount == 0 ? "No report" : row.ReportCount == 1 ? "1 report" : $"{row.ReportCount} reports",
                Money(row.FeeCents),
                row.Eligible,
                row.PayoutState,
                payoutLabel,
                tone,
                string.IsNullOrWhiteSpace(row.PayoutReference) ? "-" : row.PayoutReference,
                row.PaidAt is null ? "-" : row.PaidAt.Value.ToString("yyyy-MM-dd"),
                usage.State,
                usage.Days,
                usage.Detail,
                usage.Tone,
                usage.Tooltip));
        }

        var totals = dto.Totals;
        return new AdminTesterDetail
        {
            Name = dto.Tester.DisplayName,
            Email = dto.Tester.Email ?? "-",
            Google = dto.Tester.GoogleEmail,
            Region = string.IsNullOrWhiteSpace(dto.Tester.Region) ? "No region" : dto.Tester.Region,
            Devices = dto.Tester.Devices is null || dto.Tester.Devices.Count == 0
                ? "No devices listed"
                : string.Join(", ", dto.Tester.Devices),
            Status = dto.Tester.IsActive ? "Active" : "Inactive",
            Created = dto.Tester.CreatedAt.ToString("yyyy-MM-dd"),
            ProjectsLabel = $"{totals.Projects} projects / {totals.ActiveSeats} active seats",
            ReportsLabel = totals.Reports == 1 ? "1 report" : $"{totals.Reports} reports",
            EligibleLabel = $"{Money(totals.EligibleCents)} - {totals.EligibleCount} projects",
            DueLabel = Money(totals.DueCents),
            PaidLabel = Money(totals.PaidCents),
            UsageAvailable = dto.UsageAvailable,
            Campaigns = campaigns,
        };
    }

    private static UsageLabels BuildUsageLabels(AdminTesterUsageDto? usage, bool available)
    {
        if (!available)
        {
            return new UsageLabels(
                "Update needed",
                "Run 028",
                "Usage unavailable",
                "muted",
                "Run sql/migrations/028_admin_usage_visibility.sql in Supabase, then reopen this tester.");
        }

        if (usage is null)
        {
            return new UsageLabels(
                "Not reported",
                "No mobile data",
                "No usage yet",
                "muted",
                "The TesterLoop mobile app has not reported install or usage data for this project yet.");
        }

        var state = usage.MeetsUsageRequirement ? "Met" : usage.Installed ? "In progress" : "Not installed";
        var tone = usage.MeetsUsageRequirement ? "good" : usage.Installed ? "warn" : "muted";
        var days = $"{usage.ContinuousDaysUsed}/{AppConfig.RequiredDays} days";
        var detail = usage.LastUsageAt is null ? "No usage yet" : $"Last used {usage.LastUsageAt:yyyy-MM-dd}";
        var tooltip = string.Join(Environment.NewLine,
            $"Installed: {(usage.Installed ? "yes" : "no")}",
            $"Continuous: {usage.ContinuousDaysUsed}/{AppConfig.RequiredDays} days",
            $"Distinct: {usage.DistinctDaysUsed} days",
            usage.LastUsageAt is null ? "Last used: not reported" : $"Last used: {usage.LastUsageAt:yyyy-MM-dd HH:mm}",
            usage.FirstInstallAt is null ? "First install: not reported" : $"First install: {usage.FirstInstallAt:yyyy-MM-dd HH:mm}");

        return new UsageLabels(state, days, detail, tone, tooltip);
    }

    private sealed record UsageLabels(
        string State,
        string Days,
        string Detail,
        string Tone,
        string Tooltip);

    private static string Money(int cents) => $"${cents / 100m:0.00}";
}
