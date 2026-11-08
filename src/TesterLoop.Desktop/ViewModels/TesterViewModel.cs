using System.Collections.ObjectModel;
using System.Net;
using System.Net.Http;
using System.Windows;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Notifications;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class TesterViewModel : ObservableObject
{
    private readonly Guid _testerId;
    private readonly SupabaseService _service;
    private readonly NotificationCenter _notifications;

    private string _toast = string.Empty;
    private string _error = string.Empty;
    private string _name = string.Empty;
    private string _email = string.Empty;
    private string _region = string.Empty;
    private decimal _reliability;

    private TesterCampaignRow? _selectedReportCampaign;
    private SeverityOption _selectedSeverity;
    private string _reportTitle = string.Empty;
    private string _reportBody = string.Empty;
    private string _reportBuild = string.Empty;
    private string _reportDevice = string.Empty;
    private string _reportEvidence = string.Empty;

    public TesterViewModel(
        Guid testerId, SupabaseService service, NotificationCenter notifications)
    {
        _testerId = testerId;
        _service = service;
        _notifications = notifications;
        _selectedSeverity = Severities[2];

        Mine = [];
        Available = [];
        MyReports = [];

        JoinCommand = new AsyncRelayCommand<AvailableRow>(JoinAsync);
        OptInCommand = new AsyncRelayCommand<TesterCampaignRow>(SetOptInAsync);
        OpenCommand = new RelayCommand(p => OpenLink(p as TesterCampaignRow));
        OpenGroupCommand = new RelayCommand(p => OpenGroup(p as TesterCampaignRow));
        FileReportCommand = new AsyncRelayCommand(FileReportAsync, CanFileReport);
        RefreshCommand = new AsyncRelayCommand(LoadAsync);
    }

    public Guid TesterId => _testerId;

    public ObservableCollection<TesterCampaignRow> Mine { get; }

    public ObservableCollection<AvailableRow> Available { get; }

    public ObservableCollection<TesterReportRow> MyReports { get; }

    public IReadOnlyList<SeverityOption> Severities { get; } =
    [
        new("blocker", "Blocker"),
        new("major", "Major"),
        new("minor", "Minor"),
        new("cosmetic", "Cosmetic"),
    ];

    public AsyncRelayCommand<AvailableRow> JoinCommand { get; }

    public AsyncRelayCommand<TesterCampaignRow> OptInCommand { get; }

    public RelayCommand OpenCommand { get; }

    public RelayCommand OpenGroupCommand { get; }

    public AsyncRelayCommand FileReportCommand { get; }

    public AsyncRelayCommand RefreshCommand { get; }

    public string Name
    {
        get => _name;
        private set => Set(ref _name, value);
    }

    public string Email
    {
        get => _email;
        private set => Set(ref _email, value);
    }

    public string Region
    {
        get => _region;
        private set => Set(ref _region, value);
    }

    public string ReliabilityLabel => $"{_reliability:0.#}%";

    public string ProjectCountLabel => $"{Mine.Count}";

    public string ActiveCount => $"{Mine.Count(c => c.IsOptedIn)} active";

    public string MineCountLabel => $"{Mine.Count} joined";

    public string AvailableLabel => $"{Available.Count} open";

    public string ReportsLabel => $"{MyReports.Count} report{(MyReports.Count == 1 ? string.Empty : "s")}";

    public bool HasMine => Mine.Count > 0;

    public bool HasAvailable => Available.Count > 0;

    public bool HasReports => MyReports.Count > 0;

    public TesterCampaignRow? SelectedReportCampaign
    {
        get => _selectedReportCampaign;
        set
        {
            if (Set(ref _selectedReportCampaign, value))
            {
                FileReportCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public SeverityOption SelectedSeverity
    {
        get => _selectedSeverity;
        set => Set(ref _selectedSeverity, value);
    }

    public string ReportTitle
    {
        get => _reportTitle;
        set
        {
            if (Set(ref _reportTitle, value))
            {
                FileReportCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string ReportBody
    {
        get => _reportBody;
        set => Set(ref _reportBody, value);
    }

    public string ReportBuild
    {
        get => _reportBuild;
        set => Set(ref _reportBuild, value);
    }

    public string ReportDevice
    {
        get => _reportDevice;
        set => Set(ref _reportDevice, value);
    }

    public string ReportEvidence
    {
        get => _reportEvidence;
        set => Set(ref _reportEvidence, value);
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

        try
        {
            var dashboard = await _service.GetTesterDashboardAsync();
            Name = dashboard.Tester.DisplayName;
            Email = dashboard.Tester.Email;
            Region = dashboard.Tester.Region ?? "No region set";
            _reliability = dashboard.Tester.Reliability;
            LoadProfile(dashboard.Tester);
            LoadMobileDevice(dashboard.Tester);

            Mine.Clear();
            foreach (var campaign in dashboard.Mine)
            {
                var optedIn = campaign.State == "opted_in";
                var verified = campaign.OptInVerifiedAt is not null;
                var status = optedIn
                    ? verified ? "Opted in - verified" : "Opted in - unverified"
                    : "Joined";
                var note = optedIn
                    ? verified
                        ? "Google Group check passed"
                        : "Opted in before Google Group verification"
                    : "Confirm opt-in in the TesterLoop mobile app";

                Mine.Add(new TesterCampaignRow(
                    campaign.CampaignId,
                    campaign.AppName,
                    string.IsNullOrWhiteSpace(campaign.GroupEmail) ? "—" : campaign.GroupEmail,
                    campaign.GroupName ?? string.Empty,
                    status,
                    optedIn && verified ? "good" : "warn",
                    campaign.ClockStartedAt is null && campaign.Days == 0
                        ? "Clock not started"
                        : $"{campaign.Days} of {AppConfig.RequiredDays} days",
                    $"Seat {campaign.SeatNumber:00}",
                    campaign.PlayOptInUrl,
                    optedIn ? "Opt out" : "Leave project",
                    optedIn,
                    note));
            }

            Available.Clear();
            foreach (var campaign in dashboard.Available)
            {
                Available.Add(new AvailableRow(
                    campaign.CampaignId,
                    campaign.AppName,
                    campaign.PackageName,
                    campaign.SeatsFree,
                    $"{campaign.SeatsFree} of {AppConfig.SeatCap} seats free",
                    $"Needs {campaign.RequiredTesters} testers · {AppConfig.RequiredDays} days",
                    string.IsNullOrWhiteSpace(campaign.GroupEmail) ? "—" : campaign.GroupEmail,
                    campaign.GroupName ?? string.Empty));
            }

            MyReports.Clear();
            foreach (var report in dashboard.Reports)
            {
                MyReports.Add(new TesterReportRow(
                    report.Id,
                    report.AppName,
                    SeverityLabel(report.Severity),
                    ReportStatus(report.Status),
                    report.Title,
                    SeverityTone(report.Severity),
                    Ago(report.CreatedAt),
                    report.Usage is null
                        ? "Usage not captured"
                        : !report.Usage.Available
                            ? "Usage not reported"
                            : $"{(report.Usage.Installed ? "Installed" : "Not installed")} · "
                              + $"{report.Usage.ContinuousDaysUsed}/{AppConfig.RequiredDays} days"));
            }

            var selectedId = SelectedReportCampaign?.CampaignId;
            SelectedReportCampaign = Mine.FirstOrDefault(c => c.CampaignId == selectedId)
                                     ?? Mine.FirstOrDefault();

            Raise(string.Empty);
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private bool CanFileReport()
        => SelectedReportCampaign is not null && ReportTitle.Trim().Length >= 4;
}
