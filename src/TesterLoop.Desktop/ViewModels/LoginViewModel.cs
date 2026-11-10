using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Models;

namespace TesterLoop.Desktop.ViewModels;

public sealed class LoginViewModel : ObservableObject
{
    private const string ActivationMessage =
        "Your TesterLoop account is not activated yet. Open the activation email we sent, then sign in again.";

    private readonly SupabaseService _service;
    private readonly Func<Account, Task> _onSignedIn;

    private string _selectedRole = "Developer";
    private string _email = string.Empty;
    private string _password = string.Empty;
    private string _error = string.Empty;
    private string _notice;
    private string _resendStatus = string.Empty;
    private bool _showResend;

    public LoginViewModel(
        SupabaseService service,
        Func<Account, Task> onSignedIn,
        Action onSignUp,
        Action onForgotPassword,
        string? notice = null)
    {
        _service = service;
        _onSignedIn = onSignedIn;
        _notice = notice ?? string.Empty;
        _email = LastLoginStore.Load(LastLoginStore.MainApp) ?? string.Empty;
        SignInCommand = new AsyncRelayCommand(SignInAsync);
        SignUpCommand = new RelayCommand(onSignUp);
        ForgotPasswordCommand = new RelayCommand(onForgotPassword);
        ResendActivationCommand = new AsyncRelayCommand(ResendActivationAsync);
    }

    public AsyncRelayCommand SignInCommand { get; }

    public RelayCommand SignUpCommand { get; }

    public RelayCommand ForgotPasswordCommand { get; }

    public AsyncRelayCommand ResendActivationCommand { get; }

    public IReadOnlyList<string> Roles { get; } = ["Developer", "Tester"];

    public string SelectedRole
    {
        get => _selectedRole;
        set
        {
            if (Set(ref _selectedRole, value))
            {
                ClearMessages();
            }
        }
    }

    public string Email
    {
        get => _email;
        set
        {
            if (Set(ref _email, value))
            {
                ClearMessages();
            }
        }
    }

    public string Password
    {
        get => _password;
        set
        {
            if (Set(ref _password, value))
            {
                ClearMessages();
            }
        }
    }

    public string Error => _error;

    public bool HasError => _error.Length > 0;

    public string Notice => _notice;

    public bool HasNotice => _notice.Length > 0;

    public bool ShowResend => _showResend;

    public string ResendStatus => _resendStatus;

    public bool HasResendStatus => _resendStatus.Length > 0;

    private async Task SignInAsync()
    {
        if (string.IsNullOrWhiteSpace(_email) || string.IsNullOrEmpty(_password))
        {
            SetError("Enter your email and password.");
            return;
        }

        try
        {
            var role = SelectedRole == "Tester" ? UserRole.Tester : UserRole.Developer;
            var account = await _service.SignInAsync(_email, _password, role);
            _password = string.Empty;
            Raise(nameof(Password));
            await _onSignedIn(account);
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            if (ex.Message.StartsWith(ActivationMessage, StringComparison.Ordinal))
            {
                await _service.AbandonSessionAsync();
            }

            SetError(ex.Message);
        }
    }

    private async Task ResendActivationAsync()
    {
        if (string.IsNullOrWhiteSpace(_email))
        {
            SetError("Enter the email address you signed up with.");
            return;
        }

        try
        {
            await _service.RequestActivationAsync(_email.Trim());
            SetNotice(
                "If that address has an unactivated account, we sent a new activation email.");
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            SetError(ex.Message);
        }
    }

    private void ClearMessages()
    {
        _notice = string.Empty;
        _resendStatus = string.Empty;
        _showResend = false;
        Raise(nameof(Notice));
        Raise(nameof(HasNotice));
        Raise(nameof(ResendStatus));
        Raise(nameof(HasResendStatus));
        Raise(nameof(ShowResend));

        if (_error.Length == 0)
        {
            return;
        }

        _error = string.Empty;
        Raise(nameof(Error));
        Raise(nameof(HasError));
    }

    private void SetError(string message)
    {
        _error = message;
        _notice = string.Empty;
        _resendStatus = string.Empty;
        _showResend = message.StartsWith(ActivationMessage, StringComparison.Ordinal);
        Raise(nameof(Error));
        Raise(nameof(HasError));
        Raise(nameof(Notice));
        Raise(nameof(HasNotice));
        Raise(nameof(ResendStatus));
        Raise(nameof(HasResendStatus));
        Raise(nameof(ShowResend));
    }

    private void SetNotice(string message)
    {
        _error = string.Empty;
        _notice = message;
        _resendStatus = message;
        _showResend = true;
        Raise(nameof(Error));
        Raise(nameof(HasError));
        Raise(nameof(Notice));
        Raise(nameof(HasNotice));
        Raise(nameof(ResendStatus));
        Raise(nameof(HasResendStatus));
        Raise(nameof(ShowResend));
    }
}
