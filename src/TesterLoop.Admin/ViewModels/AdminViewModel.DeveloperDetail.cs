using System.Collections.ObjectModel;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private AdminDeveloperDetail? _developerDetail;
    private DeveloperRow? _selectedDeveloperRow;
    private int _developerPageIndex;

    public RelayCommand BackToDevelopersCommand { get; private set; } = null!;

    public AdminDeveloperDetail? DeveloperDetail
    {
        get => _developerDetail;
        private set => Set(ref _developerDetail, value);
    }

    public int DeveloperPageIndex
    {
        get => _developerPageIndex;
        set => Set(ref _developerPageIndex, value);
    }

    public DeveloperRow? SelectedDeveloperRow
    {
        get => _selectedDeveloperRow;
        set
        {
            if (Set(ref _selectedDeveloperRow, value) && value is not null && _developerPageIndex == 0)
            {
                _ = OpenDeveloperAsync(value.Id);
            }
        }
    }

    public async Task OpenDeveloperAsync(Guid developerId)
    {
        Error = string.Empty;
        Toast = string.Empty;

        try
        {
            var detail = await _service.GetAdminDeveloperDetailAsync(developerId);
            DeveloperDetail = MapDeveloperDetail(detail);
            DeveloperPageIndex = 1;
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
            DeveloperPageIndex = 0;
            _selectedDeveloperRow = null;
            Raise(nameof(SelectedDeveloperRow));
        }
    }

    private void BackToDevelopers()
    {
        DeveloperPageIndex = 0;
        _selectedDeveloperRow = null;
        Raise(nameof(SelectedDeveloperRow));
        DeveloperDetail = null;
    }

    private static AdminDeveloperDetail MapDeveloperDetail(AdminDeveloperDetailDto dto)
    {
        var totals = dto.Totals;

        var campaigns = new ObservableCollection<AdminDeveloperCampaignRow>();
        foreach (var campaign in dto.Campaigns ?? [])
        {
            campaigns.Add(new AdminDeveloperCampaignRow(
                campaign.AppName,
                campaign.PackageName,
                StateLabel(campaign.State),
                Tone(campaign.State),
                PaymentLabel(campaign.PaymentState, campaign.PaymentAmountCents),
                PaymentTone(campaign.PaymentState),
                $"{campaign.OptedIn} / {campaign.TestersUsed} opted in",
                $"{campaign.TestersUsed} testers · {campaign.SeatsUsed} seats",
                campaign.CreatedAt.ToString("yyyy-MM-dd")));
        }

        var groups = new ObservableCollection<AdminDeveloperGroupRow>();
        foreach (var group in dto.Groups ?? [])
        {
            groups.Add(new AdminDeveloperGroupRow(
                group.Email,
                string.IsNullOrWhiteSpace(group.Name) ? "—" : group.Name,
                GroupLabel(group.State),
                "Manual check"));
        }

        var testers = new ObservableCollection<AdminDeveloperTesterRow>();
        foreach (var tester in dto.Testers ?? [])
        {
            testers.Add(new AdminDeveloperTesterRow(
                tester.DisplayName,
                tester.GoogleEmail,
                tester.Campaigns == 1 ? "1 project" : $"{tester.Campaigns} projects",
                tester.Reports == 1 ? "1 report" : $"{tester.Reports} reports",
                Money(tester.DueCents),
                Money(tester.PaidCents)));
        }

        var audit = new ObservableCollection<AuditRow>();
        foreach (var entry in dto.Audit ?? [])
        {
            audit.Add(new AuditRow(
                entry.CreatedAt,
                Ago(entry.CreatedAt),
                entry.ActorLabel,
                entry.Action,
                entry.Target ?? "—"));
        }

        return new AdminDeveloperDetail
        {
            Company = dto.Developer.CompanyName,
            DisplayName = string.IsNullOrWhiteSpace(dto.Developer.DisplayName)
                ? "No profile name"
                : dto.Developer.DisplayName,
            Contact = dto.Developer.ContactEmail,
            Google = dto.Developer.GoogleEmail,
            Created = dto.Developer.CreatedAt.ToString("yyyy-MM-dd"),
            ProjectsLabel = $"{totals.Projects} projects · {totals.Live} live · {totals.Passed} passed",
            TestersLabel = $"{totals.TestersUsed} testers used · {totals.ActiveSeats} active seats",
            FeesPaidLabel = Money(totals.ProjectFeesPaidCents),
            FeesDueLabel = Money(totals.ProjectFeesDueCents),
            PayoutsPaidLabel = Money(totals.TesterPayoutsPaidCents),
            PayoutsDueLabel = Money(totals.TesterPayoutsDueCents),
            Campaigns = campaigns,
            Groups = groups,
            Testers = testers,
            Audit = audit,
        };
    }
}
