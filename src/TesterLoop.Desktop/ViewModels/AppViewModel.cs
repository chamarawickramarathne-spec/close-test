using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Models;

namespace TesterLoop.Desktop.ViewModels;

public sealed class AppViewModel : ObservableObject
{
    private readonly SupabaseService _service = new();
    private object _current;

    public AppViewModel()
    {
        _current = CreateLogin();
    }

    public object Current
    {
        get => _current;
        private set => Set(ref _current, value);
    }

    private LoginViewModel CreateLogin(string? notice = null)
        => new(_service, SignedInAsync, ShowSignUp, ShowPasswordReset, notice);

    private async Task SignedInAsync(Account account)
    {
        if (account.Role == UserRole.Admin)
        {
            await _service.SignOutAsync();
            throw new InvalidOperationException(
                "Operations staff use TesterLoop Admin. This app is for developers and testers.");
        }

        LastLoginStore.Save(LastLoginStore.MainApp, account.Email);
        var shell = new ShellViewModel(account, _service, ShowSignIn);
        Current = shell;
        await shell.InitializeAsync();
    }

    private void ShowSignIn() => Current = CreateLogin();

    private void ShowSignUp()
        => Current = new SignUpViewModel(_service, ShowSignIn);

    private void ShowPasswordReset()
        => Current = new ResetPasswordViewModel(
            _service,
            message => Current = CreateLogin(message),
            ShowSignIn);
}
