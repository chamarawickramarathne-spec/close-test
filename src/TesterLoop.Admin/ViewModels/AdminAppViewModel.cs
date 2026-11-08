using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;
using TesterLoop.Desktop.Core.Models;

namespace TesterLoop.Admin.ViewModels;

public sealed class AdminAppViewModel : ObservableObject
{
    private readonly SupabaseService _service = new();
    private object _current;

    public AdminAppViewModel()
    {
        _current = CreateLogin();
    }

    public object Current
    {
        get => _current;
        private set => Set(ref _current, value);
    }

    private AdminLoginViewModel CreateLogin()
        => new(_service, SignedInAsync);

    private async Task SignedInAsync(Account account)
    {
        LastLoginStore.Save(LastLoginStore.AdminApp, account.Email);
        var shell = new AdminShellViewModel(account, _service, ShowSignIn);
        Current = shell;
        await shell.InitializeAsync();
    }

    private void ShowSignIn() => Current = CreateLogin();
}
