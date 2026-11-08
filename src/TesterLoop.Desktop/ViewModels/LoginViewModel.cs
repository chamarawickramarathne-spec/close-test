using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Models;

namespace TesterLoop.Desktop.ViewModels;

public sealed class LoginViewModel : ObservableObject
{
    private readonly SupabaseService _service;
    private readonly Func<Account, Task> _onSignedIn;

    private string _selectedRole = "Developer";
    private string _email = string.Empty;
    private string _password = string.Empty;
    private string _error = string.Empty;
    private string _notice;

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
    }

    public AsyncRelayCommand SignInCommand { get; }

    public RelayCommand SignUpCommand { get; }

    public RelayCommand ForgotPasswordCommand { get; }

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
            SetError(ex.Message);
        }
    }

    private void ClearMessages()
    {
        _notice = string.Empty;
        Raise(nameof(Notice));
        Raise(nameof(HasNotice));

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
        Raise(nameof(Error));
        Raise(nameof(HasError));
        Raise(nameof(Notice));
        Raise(nameof(HasNotice));
    }
}
