using System.Net.Http;
using System.Text.RegularExpressions;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class SignUpViewModel : ObservableObject
{
    private readonly SupabaseService _service;

    private string _selectedRole = "Developer";
    private string _displayName = string.Empty;
    private string _companyName = string.Empty;
    private string _region = string.Empty;
    private string _devices = "Android phone";
    private string _email = string.Empty;
    private string _password = string.Empty;
    private string _error = string.Empty;
    private string _createdEmail = string.Empty;
    private string _resendStatus = string.Empty;

    public SignUpViewModel(SupabaseService service, Action onBack)
    {
        _service = service;
        CreateCommand = new AsyncRelayCommand(CreateAsync);
        ResendCommand = new AsyncRelayCommand(ResendAsync);
        BackCommand = new RelayCommand(onBack);
    }

    public IReadOnlyList<string> Roles { get; } = ["Developer", "Tester"];

    public AsyncRelayCommand CreateCommand { get; }

    public AsyncRelayCommand ResendCommand { get; }

    public RelayCommand BackCommand { get; }

    public string SelectedRole
    {
        get => _selectedRole;
        set
        {
            if (Set(ref _selectedRole, value))
            {
                Raise(nameof(IsDeveloper));
                Raise(nameof(IsTester));
                Error = string.Empty;
            }
        }
    }

    public bool IsDeveloper => SelectedRole != "Tester";

    public bool IsTester => !IsDeveloper;

    public bool IsCreated => _createdEmail.Length > 0;

    public bool IsFormVisible => !IsCreated;

    public string CreatedEmail => _createdEmail;

    public string DisplayName
    {
        get => _displayName;
        set => Set(ref _displayName, value);
    }

    public string CompanyName
    {
        get => _companyName;
        set => Set(ref _companyName, value);
    }

    public string Region
    {
        get => _region;
        set => Set(ref _region, value);
    }

    public string Devices
    {
        get => _devices;
        set => Set(ref _devices, value);
    }

    public string Email
    {
        get => _email;
        set => Set(ref _email, value);
    }

    public string Password
    {
        get => _password;
        set => Set(ref _password, value);
    }

    public string Error
    {
        get => _error;
        set
        {
            if (Set(ref _error, value))
            {
                Raise(nameof(HasError));
            }
        }
    }

    public bool HasError => Error.Length > 0;

    public string ResendStatus
    {
        get => _resendStatus;
        set
        {
            if (Set(ref _resendStatus, value))
            {
                Raise(nameof(HasResendStatus));
            }
        }
    }

    public bool HasResendStatus => ResendStatus.Length > 0;

    public string RoleHint => IsDeveloper
        ? "Create a company workspace for your apps."
        : "Join campaigns and file reports as a freelance tester.";

    private async Task CreateAsync()
    {
        var problem = Validate();
        if (problem is not null)
        {
            Error = problem;
            return;
        }

        try
        {
            var outcome = IsDeveloper
                ? await _service.SignUpDeveloperAsync(
                    Email, Password, DisplayName, CompanyName)
                : await _service.SignUpTesterAsync(
                    Email, Password, DisplayName, Region, Devices);

            _password = string.Empty;
            Raise(nameof(Password));
            _createdEmail = outcome.Email;
            Error = string.Empty;
            Raise(nameof(IsCreated));
            Raise(nameof(IsFormVisible));
            Raise(nameof(CreatedEmail));
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private async Task ResendAsync()
    {
        if (IsCreated)
        {
            Email = _createdEmail;
        }

        if (!LooksLikeEmail(Email))
        {
            Error = "Enter the email address you signed up with.";
            return;
        }

        try
        {
            await _service.RequestActivationAsync(Email.Trim());
            Error = string.Empty;
            ResendStatus =
                "If that address has an unactivated account, we sent a new activation email.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            ResendStatus = string.Empty;
            Error = ex.Message;
        }
    }

    private string? Validate()
    {
        if (DisplayName.Trim().Length < 2)
        {
            return "Enter the name that should appear on your account.";
        }

        if (!LooksLikeEmail(Email))
        {
            return "Enter a valid email address.";
        }

        if (Password.Length < 8)
        {
            return "Use a password with at least 8 characters.";
        }

        if (IsDeveloper && CompanyName.Trim().Length < 2)
        {
            return "Enter your company or studio name.";
        }

        if (IsTester && Devices.Trim().Length == 0)
        {
            return "List at least one device you test on.";
        }

        return null;
    }

    private static bool LooksLikeEmail(string value)
        => EmailPattern().IsMatch(value.Trim());

    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$")]
    private static partial Regex EmailPattern();
}
