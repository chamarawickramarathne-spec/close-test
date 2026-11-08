using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Models;

namespace TesterLoop.Admin.ViewModels;

public sealed class AdminLoginViewModel : ObservableObject
{
    private readonly SupabaseService _service;
    private readonly Func<Account, Task> _onSignedIn;

    private string _email = string.Empty;
    private string _password = string.Empty;
    private string _error = string.Empty;

    public AdminLoginViewModel(SupabaseService service, Func<Account, Task> onSignedIn)
    {
        _service = service;
        _onSignedIn = onSignedIn;
        _email = LastLoginStore.Load(LastLoginStore.AdminApp) ?? string.Empty;
        SignInCommand = new AsyncRelayCommand(SignInAsync);
    }

    public AsyncRelayCommand SignInCommand { get; }

    public string Email
    {
        get => _email;
        set
        {
            if (Set(ref _email, value))
            {
                ClearError();
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
                ClearError();
            }
        }
    }

    public string Error => _error;

    public bool HasError => _error.Length > 0;

    private async Task SignInAsync()
    {
        if (string.IsNullOrWhiteSpace(_email) || string.IsNullOrEmpty(_password))
        {
            SetError("Enter your operations email and password.");
            return;
        }

        try
        {
            var account = await _service.SignInAsync(_email, _password);
            _password = string.Empty;
            Raise(nameof(Password));

            if (account.Role != UserRole.Admin)
            {
                await _service.SignOutAsync();
                throw new InvalidOperationException(
                    "This app is for TesterLoop operations staff. Use TesterLoop for developer or tester accounts.");
            }

            await _onSignedIn(account);
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            SetError(ex.Message);
        }
    }

    private void ClearError()
    {
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
        Raise(nameof(Error));
        Raise(nameof(HasError));
    }
}
