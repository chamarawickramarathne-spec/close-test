using System.Collections.ObjectModel;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Notifications;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel : ObservableObject
{
    private readonly SupabaseService _service;
    private readonly NotificationCenter _notifications;
    private AdminCountsDto _counts = new(0, 0, 0, 0, 0);
    private string _toast = string.Empty;
    private string _error = string.Empty;

    public AdminViewModel(SupabaseService service, NotificationCenter notifications)
    {
        _service = service;
        _notifications = notifications;
        Payments = [];
        GroupSetup = [];
        Groups = [];
        Campaigns = [];
        Audit = [];
        Packages = [];

        ConfirmPaymentCommand = new AsyncRelayCommand(ConfirmPaymentAsync);
        ManualCheckCommand = new RelayCommand(ManualCheck);
        RefreshCommand = new AsyncRelayCommand(LoadAsync);
        SaveProfileCommand = new AsyncRelayCommand(SaveProfileAsync);
        MarkTesterPaidCommand = new AsyncRelayCommand<AdminTesterCampaignRow>(MarkTesterPaidAsync);
        BackToTestersCommand = new RelayCommand(BackToTesters);
        BackToCampaignsCommand = new RelayCommand(BackToCampaigns);
        RefreshCampaignCommand = new AsyncRelayCommand(RefreshCampaignAsync);
        BackToDevelopersCommand = new RelayCommand(BackToDevelopers);
        BackToFeedbackCommand = new RelayCommand(BackToFeedback);
        CopyReportEvidenceCommand = new RelayCommand(CopyReportEvidence);
        AttachGroupCommand = new AsyncRelayCommand(AttachGroupAsync);
        RotateGroupCommand = new AsyncRelayCommand(RotateGroupAsync);
        CopyReservedEmailCommand = new RelayCommand(CopyReservedEmail);
        CopyReservedDisplayCommand = new RelayCommand(CopyReservedDisplay);
        OpenGroupsCommand = new RelayCommand(OpenGroups);
        OpenGroupCreateCommand = new RelayCommand(OpenGroupCreate);
        CopyReservedUrlNameCommand = new RelayCommand(CopyReservedUrlName);
        SavePackageCommand = new AsyncRelayCommand(SavePackageAsync);
        NewPackageCommand = new RelayCommand(StartNewPackage);
        EditPackageCommand = new AsyncRelayCommand<PaymentPackageRow>(EditPackageAsync);
        DeletePackageCommand = new AsyncRelayCommand(DeletePackageAsync);
        ClosePackageCommand = new RelayCommand(ClosePackage);
    }

    public ObservableCollection<PaymentRow> Payments { get; }

    public ObservableCollection<GroupSetupRow> GroupSetup { get; }

    public ObservableCollection<GroupRow> Groups { get; }

    public ObservableCollection<AdminCampaignRow> Campaigns { get; }

    public ObservableCollection<AuditRow> Audit { get; }

    public ObservableCollection<PaymentPackageRow> Packages { get; }

    public string AuditCountLabel => Audit.Count == 1 ? "1 entry" : $"{Audit.Count} entries";

    public bool HasAudit => Audit.Count > 0;

    public AsyncRelayCommand RefreshCommand { get; }

    public RelayCommand ManualCheckCommand { get; }

    public string DeveloperCount => _counts.Developers.ToString();

    public string GroupCount => _counts.Groups.ToString();

    public string LiveCount => _counts.Active.ToString();

    public string TesterCount => _counts.Testers.ToString();

    public string PendingCount => _counts.Pending.ToString();

    public string ManualLabel => $"{Groups.Count} manual groups - no API sync";

    public string Toast
    {
        get => _toast;
        private set
        {
            var message = value ?? string.Empty;
            if (message.Length > 0)
            {
                _notifications.Success(message);
            }

            if (Set(ref _toast, string.Empty))
            {
                Raise(nameof(HasToast));
            }
        }
    }

    public bool HasToast => Toast.Length > 0;

    public string Error
    {
        get => _error;
        private set
        {
            if (Set(ref _error, value))
            {
                Raise(nameof(HasError));
            }
        }
    }

    public bool HasError => Error.Length > 0;

    public async Task LoadAsync()
    {
        Error = string.Empty;

        try
        {
            var dashboard = await _service.GetAdminDashboardAsync();
            _counts = dashboard.Counts;

            LoadPayments(dashboard);
            LoadGroupSetup(dashboard);

            Groups.Clear();
            foreach (var group in dashboard.Groups)
            {
                Groups.Add(new GroupRow(
                    group.Email,
                    string.IsNullOrWhiteSpace(group.Name) ? "-" : group.Name,
                    string.IsNullOrWhiteSpace(group.DisplayName) ? "-" : group.DisplayName,
                    group.Developer,
                    group.Members is null ? "Manual check" : group.Members.Value.ToString(),
                    group.SettingsConfirmedAt is null ? "Settings not recorded" : "Settings confirmed",
                    GroupLabel(group.State),
                    GroupTone(group.State)));
            }

            Campaigns.Clear();
            foreach (var campaign in dashboard.Campaigns)
            {
                Campaigns.Add(new AdminCampaignRow(
                    campaign.Id,
                    campaign.AppName,
                    campaign.Developer,
                    campaign.PackageName ?? "-",
                    StateLabel(campaign.State),
                    Tone(campaign.State),
                    PaymentLabel(campaign.PaymentState, campaign.PaymentAmountCents),
                    PaymentTone(campaign.PaymentState),
                    $"{campaign.OptedIn} / {campaign.RequiredTesters}",
                    $"{campaign.TestersUsed} / {AppConfig.SeatCap}"));
            }

            LoadTabs(dashboard);
            LoadPackages(dashboard);

            if (dashboard.Developers is null || dashboard.Testers is null || dashboard.Profile is null)
            {
                Error = "The admin tabs need a database update. Run "
                        + "sql/migrations/009_admin_tabs_profile.sql in Supabase, then press Refresh.";
            }
            else if (dashboard.Payments is null)
            {
                Error = "The payments queue needs a database update. Run "
                        + "sql/migrations/012_project_payments.sql in Supabase, then press Refresh.";
            }
            else if (dashboard.GroupSetup is null)
            {
                Error = "The group setup queue needs a database update. Run "
                        + "sql/migrations/021_assisted_group_provisioning.sql in Supabase, then press Refresh.";
            }
            else if (dashboard.Packages is null)
            {
                Error = "The payment packages tab needs a database update. Run "
                        + "sql/migrations/026_payment_packages.sql in Supabase, then press Refresh.";
            }

            Audit.Clear();
            foreach (var entry in dashboard.Audit)
            {
                Audit.Add(new AuditRow(
                    entry.CreatedAt,
                    Ago(entry.CreatedAt),
                    entry.ActorLabel,
                    entry.Action,
                    entry.Target ?? "-"));
            }

            Raise(nameof(AuditCountLabel));
            Raise(nameof(HasAudit));
            Raise(nameof(ManualLabel));
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private void ManualCheck()
    {
        Toast = "Google Groups are created and checked by hand in groups.google.com. The app records which settings were confirmed, but it cannot read them back.";
    }

    private static string Ago(DateTime at)
    {
        var span = DateTime.Now - at;
        if (span.TotalHours < 1)
        {
            return "just now";
        }

        return span.TotalHours < 24 ? $"{(int)span.TotalHours} h ago" : $"{(int)span.TotalDays} d ago";
    }
}
