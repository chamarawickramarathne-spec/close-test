using System.Collections.ObjectModel;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Windows;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Notifications;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class DeveloperViewModel : ObservableObject
{
    private readonly Guid _developerId;
    private readonly SupabaseService _service;
    private readonly NotificationCenter _notifications;

    private List<DeveloperCampaignDto> _allCampaigns = [];
    private DeveloperCampaignDto? _campaign;
    private CampaignOption? _selected;
    private PaymentPackageDto? _selectedPackage;
    private string _toast = string.Empty;
    private string _error = string.Empty;
    private string _packageError = string.Empty;
    private string _newAppName = string.Empty;
    private string _newPackage = string.Empty;
    private string _draftUrl = string.Empty;

    public DeveloperViewModel(
        Guid developerId, SupabaseService service, NotificationCenter notifications)
    {
        _developerId = developerId;
        _service = service;
        _notifications = notifications;

        Campaigns = [];
        CompletedCampaigns = [];
        Packages = [];
        SeatCells = [];
        Roster = [];
        Reports = [];

        CreateProjectCommand = new AsyncRelayCommand(CreateProjectAsync);
        SaveLinkCommand = new AsyncRelayCommand(SaveLinkAsync);
        DeleteProjectCommand = new AsyncRelayCommand(DeleteProjectAsync);
        DeleteCompletedCommand = new AsyncRelayCommand<CampaignOption>(DeleteCompletedAsync);
        FreeAccessCommand = new AsyncRelayCommand(ClaimFreeAccessAsync);

        CopyGroupCommand = new RelayCommand(CopyGroup);
        CopyOptInCommand = new RelayCommand(CopyOptIn);
        OpenLinkCommand = new RelayCommand(OpenLink);
        RefreshCommand = new AsyncRelayCommand(LoadAsync);
    }

    public Guid DeveloperId => _developerId;

    public ObservableCollection<CampaignOption> Campaigns { get; }

    public ObservableCollection<CampaignOption> CompletedCampaigns { get; }

    public ObservableCollection<PaymentPackageDto> Packages { get; }

    public ObservableCollection<SeatCell> SeatCells { get; }

    public ObservableCollection<RosterRow> Roster { get; }

    public ObservableCollection<ReportRow> Reports { get; }

    public AsyncRelayCommand CreateProjectCommand { get; }

    public AsyncRelayCommand SaveLinkCommand { get; }


    public RelayCommand CopyGroupCommand { get; }

    public RelayCommand CopyOptInCommand { get; }

    public RelayCommand OpenLinkCommand { get; }

    public AsyncRelayCommand RefreshCommand { get; }

    public CampaignOption? SelectedCampaign
    {
        get => _selected;
        set
        {
            if (!Set(ref _selected, value))
            {
                return;
            }

                _campaign = value is null ? null : _allCampaigns.FirstOrDefault(c => c.Id == value.Id);
                DraftUrl = _campaign?.PlayOptInUrl ?? string.Empty;
                ClearLinkNote();
                LoadDetail();
            Raise(string.Empty);
        }
    }

    public PaymentPackageDto? SelectedPackage
    {
        get => _selectedPackage;
        set
        {
            if (Set(ref _selectedPackage, value))
            {
                Raise(nameof(SelectedPackageFeeLabel));
                Raise(nameof(SelectedPackageDetail));
                Raise(nameof(HasSelectedPackage));
            }
        }
    }

    public bool HasPackages => Packages.Count > 0;

    public bool HasSelectedPackage => SelectedPackage is not null;

    public string SelectedPackageFeeLabel => SelectedPackage is null
        ? AppConfig.ProjectFeeLabel
        : Money(SelectedPackage.AmountCents);

    public string SelectedPackageDetail => SelectedPackage is null
        ? "Choose a package to see its project fee."
        : $"Normally {Money(SelectedPackage.AmountCents)} - free access for now";

    private static string Money(int cents)
        => "$" + (cents / 100m).ToString("0.00", System.Globalization.CultureInfo.InvariantCulture);

    public string PackageError
    {
        get => _packageError;
        private set
        {
            if (Set(ref _packageError, value))
            {
                Raise(nameof(HasPackageError));
            }
        }
    }

    public bool HasPackageError => PackageError.Length > 0;

    public string NewAppName
    {
        get => _newAppName;
        set => Set(ref _newAppName, value);
    }

    public string NewPackage
    {
        get => _newPackage;
        set => Set(ref _newPackage, value);
    }

    public string DraftUrl
    {
        get => _draftUrl;
        set => Set(ref _draftUrl, value);
    }

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
        ClearLinkNote();

        try
        {
            var dashboard = await _service.GetDeveloperDashboardAsync();
            var keep = _campaign?.Id;

            _allCampaigns = dashboard.Campaigns;
            LoadProfile(dashboard.Developer);
            await LoadPackagesAsync();

            Campaigns.Clear();
            CompletedCampaigns.Clear();
            foreach (var campaign in _allCampaigns)
            {
                var option = new CampaignOption(
                    campaign.Id,
                    campaign.AppName,
                    campaign.PackageName,
                    StateLabelFor(campaign),
                    Tone(campaign.State),
                    $"{campaign.SeatsUsed} / {AppConfig.SeatCap} seats",
                    $"{campaign.TestersUsed} / {AppConfig.SeatCap} testers",
                    !campaign.DeleteLocked,
                    campaign.DeleteLocked
                        ? $"Locked until {DeleteUnlockLabel(campaign)}"
                        : "Delete this project");

                if (campaign.State is "passed" or "cancelled")
                {
                    CompletedCampaigns.Add(option);
                }
                else
                {
                    Campaigns.Add(option);
                }
            }

            var active = _allCampaigns
                .Where(c => c.State is not ("passed" or "cancelled"))
                .ToList();
            _campaign = active.FirstOrDefault(c => c.Id == keep) ?? active.FirstOrDefault();
            _selected = _campaign is null
                ? null
                : Campaigns.FirstOrDefault(c => c.Id == _campaign.Id);

            DraftUrl = _campaign?.PlayOptInUrl ?? string.Empty;
            LoadDetail();
            Raise(string.Empty);
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private async Task SaveLinkAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;
        ClearLinkNote();

        if (_campaign is null)
        {
            Error = "Select a project first.";
            return;
        }

        if (_campaign.PaymentState != "paid")
        {
            Error = "Activate free access on the project page before you can save the link.";
            return;
        }

        if (IsLinkLocked)
        {
            Error = "A tester has already joined this project, so the closed-test link is locked.";
            return;
        }

        var url = DraftUrl.Trim();
        if (!PlayLink.IsValid(url))
        {
            Error = "Enter a Google Play testing link or store details link.";
            return;
        }

        try
        {
            await _service.SavePlayLinkAsync(_campaign.Id, url);
            await LoadAsync();
            Toast = "Testing link saved. Testers can now see this project.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }



    private void OpenLink()
    {
        Error = string.Empty;
        ClearLinkNote();
        if (string.IsNullOrWhiteSpace(_campaign?.PlayOptInUrl))
        {
            LinkIssue("Save a testing link first, then press Open.");
            return;
        }

        if (!LinkLauncher.TryOpen(_campaign.PlayOptInUrl))
        {
            LinkIssue("The browser could not be opened for that testing link.");
            return;
        }

        Toast = "Opened the testing link in your browser.";
    }

    private void CopyGroup()
    {
        Error = string.Empty;
        if (string.IsNullOrWhiteSpace(_campaign?.GroupEmail))
        {
            Error = "No group address yet. Operations will attach one first.";
            return;
        }

        Copy(_campaign.GroupEmail, "Group address copied.");
    }

    private void CopyOptIn()
    {
        Error = string.Empty;
        ClearLinkNote();
        if (string.IsNullOrWhiteSpace(_campaign?.PlayOptInUrl))
        {
            LinkIssue("Save a testing link first, then press Copy.");
            return;
        }

        Copy(_campaign.PlayOptInUrl, "Testing link copied.");
    }

    private void Copy(string text, string message)
    {
        try
        {
            Clipboard.SetText(text);
            Toast = message;
        }
        catch (ExternalException)
        {
            Error = "Clipboard is busy. Copy the value manually.";
        }
    }

}
