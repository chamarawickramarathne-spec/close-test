using System.Collections.ObjectModel;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Models;
using TesterLoop.Desktop.Core.Notifications;

namespace TesterLoop.Admin.ViewModels;

public sealed class AdminShellViewModel : ObservableObject
{
    private readonly SupabaseService _service;
    private readonly Action _onSignOut;
    private string _userName;
    private string _error = string.Empty;

    public AdminShellViewModel(Account account, SupabaseService service, Action onSignOut)
    {
        Account = account;
        _userName = account.Name;
        _service = service;
        _onSignOut = onSignOut;
        Notifications = new NotificationCenter();
        View = new AdminViewModel(service, Notifications);
        View.ProfileSaved += OnProfileSaved;
        SignOutCommand = new AsyncRelayCommand(SignOutAsync);

        NavItems.Add(new NavigationItem("Operations", () => Select(0)));
        NavItems.Add(new NavigationItem("Close Test Projects", () => Select(1)));
        NavItems.Add(new NavigationItem("Developers", () => Select(2)));
        NavItems.Add(new NavigationItem("Testers", () => Select(3)));
        NavItems.Add(new NavigationItem("Feedback", () => Select(4)));
        NavItems.Add(new NavigationItem("Payment Packages", () => Select(5)));
        NavItems.Add(new NavigationItem("Audit Trail", () => Select(6)));
        NavItems.Add(new NavigationItem("Profile", () => Select(7)));
        Select(0);
    }

    public Account Account { get; }

    public AdminViewModel View { get; }

    public NotificationCenter Notifications { get; }

    public ObservableCollection<NavigationItem> NavItems { get; } = [];

    public AsyncRelayCommand SignOutCommand { get; }

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

    public string UserName => _userName;

    public string UserEmail => Account.Email;

    public string Initials
    {
        get
        {
            var parts = UserName.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            return parts.Length switch
            {
                0 => "?",
                1 => parts[0][..1].ToUpperInvariant(),
                _ => (parts[0][..1] + parts[^1][..1]).ToUpperInvariant(),
            };
        }
    }

    public string RoleLabel => "Operations staff";

    public string RoleBadge => "OPERATIONS";

    public string HeaderTitle => "Operations";

    public string HeaderSubtitle => "Payments, manual Google Groups, close test projects, payouts and the audit trail";

    public string VersionLabel => $"v{AppConfig.AppVersion}";

    public Task InitializeAsync() => View.LoadAsync();

    private void Select(int index)
    {
        View.SelectedTabIndex = index;
        for (var i = 0; i < NavItems.Count; i++)
        {
            NavItems[i].SetActive(i == index);
        }
    }

    private void OnProfileSaved(string displayName)
    {
        _userName = displayName;
        Raise(nameof(UserName));
        Raise(nameof(Initials));
    }

    private async Task SignOutAsync()
    {
        try
        {
            await _service.SignOutAsync();
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
        finally
        {
            _onSignOut();
        }
    }
}
