using System.Text.Json;
using TesterLoop.Desktop.Core.Models;

namespace TesterLoop.Desktop.Core.Data;

public sealed partial class SupabaseService
{
    public async Task<Account> SignInAsync(string email, string password)
    {
        await AuthenticateAsync(email, password);
        return await WhoAmIAsync();
    }

    public async Task<Account> SignInAsync(string email, string password, UserRole selectedRole)
    {
        if (selectedRole is UserRole.Admin)
        {
            throw new InvalidOperationException("Operations staff use TesterLoop Admin.");
        }

        await AuthenticateAsync(email, password);

        var account = await WhoAmIAsync();
        var hasRole = selectedRole is UserRole.Tester
            ? account.TesterId is not null
            : account.DeveloperId is not null;

        if (!hasRole)
        {
            await EnsureRoleAsync(selectedRole);
            account = await WhoAmIAsync();
        }

        return account with { Role = selectedRole };
    }

    public Task<JsonElement> EnsureRoleAsync(UserRole role)
    {
        if (role is UserRole.Admin)
        {
            throw new InvalidOperationException("Operations staff use TesterLoop Admin.");
        }

        var name = role is UserRole.Tester ? "tester" : "developer";
        return RpcAsync<JsonElement>("ensure_account_role", Arguments(("p_role", name)));
    }

    private async Task AuthenticateAsync(string email, string password)
    {
        await AuthCallAsync(async () =>
        {
            await _client.Auth.SignIn(email.Trim(), password);
            return true;
        });
    }
}
