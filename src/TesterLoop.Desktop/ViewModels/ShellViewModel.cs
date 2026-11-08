using System.Collections.ObjectModel;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Models;
using TesterLoop.Desktop.Core.Notifications;

namespace TesterLoop.Desktop.ViewModels;

public sealed class ShellViewModel : ObservableObject
{
    private readonly SupabaseService _service;
    private readonly Action _onSignOut;
    private string _error = string.Empty;

    public ShellViewModel(Account account, SupabaseService service, Action onSignOut)
    {
        Account = account;
        _service = service;
        _onSignOut = onSignOut;
        Notifications = new NotificationCenter();
        SignOutCommand = new AsyncRelayCommand(SignOutAsync);

        View = account.Role switch
        {
            UserRole.Tester => new TesterViewModel(account.TesterId
                ?? throw new InvalidOperationException("Tester account has no tester record."), service, Notifications),
            UserRole.Developer => new DeveloperViewModel(account.DeveloperId
                ?? throw new InvalidOperationException("Developer account has no developer record."), service, Notifications),
            _ => throw new InvalidOperationException(
                "This workspace is for developer and tester accounts."),
        };

        BuildNavigation();
    }

    public Account Account { get; }

    public object View { get; }

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

    public string UserName => Account.Name;

    public string UserEmail => Account.Email;

    public string Initials
    {
        get
        {
            var parts = Account.Name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            return parts.Length switch
            {
                0 => "?",
                1 => parts[0][..1].ToUpperInvariant(),
                _ => (parts[0][..1] + parts[^1][..1]).ToUpperInvariant(),
            };
        }
    }

    public string RoleLabel => Account.Role switch
    {
        UserRole.Tester => "Freelance tester",
        _ => "App developer",
    };

    public string RoleBadge => Account.Role switch
    {
        UserRole.Tester => "TESTER",
        _ => "DEVELOPER",
    };

    public string HeaderTitle => Account.Role switch
    {
        UserRole.Tester => "Tester bench",
        _ => "Campaign workspace",
    };

    public string HeaderSubtitle => Account.Role switch
    {
        UserRole.Tester => "Open projects, your seats and the Play links you need",
        _ => "Projects, Google Groups and the 14-day clock",
    };

    public string VersionLabel => $"v{AppConfig.AppVersion}";

    public async Task InitializeAsync()
    {
        switch (View)
        {
            case DeveloperViewModel developer:
                await developer.LoadAsync();
                break;
            case TesterViewModel tester:
                await tester.LoadAsync();
                break;
        }
    }

    private void BuildNavigation()
    {
        if (View is DeveloperViewModel)
        {
            NavItems.Add(new NavigationItem("Workspace", () => Select(0)));
            NavItems.Add(new NavigationItem("Completed projects", () => Select(1)));
            NavItems.Add(new NavigationItem("Profile", () => Select(2)));
        }
        else
        {
            NavItems.Add(new NavigationItem("Tester bench", () => Select(0)));
            NavItems.Add(new NavigationItem("Profile", () => Select(1)));
        }

        Select(0);
    }

    private void Select(int index)
    {
        if (View is DeveloperViewModel developer)
        {
            developer.SelectedTabIndex = index;
        }
        else if (View is TesterViewModel tester)
        {
            tester.SelectedTabIndex = index;
        }

        for (var i = 0; i < NavItems.Count; i++)
        {
            NavItems[i].SetActive(i == index);
        }
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
