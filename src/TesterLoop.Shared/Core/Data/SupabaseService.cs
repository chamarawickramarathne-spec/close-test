using System.Net.Http;
using System.Text.Json;
using Supabase;
using Supabase.Gotrue;
using TesterLoop.Desktop.Core.Models;

namespace TesterLoop.Desktop.Core.Data;

public sealed partial class SupabaseService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly Supabase.Client _client;
    private readonly LiveSessionStore _store = new();
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(30) };

    public SupabaseService()
    {
        _client = new Supabase.Client(
            AppConfig.SupabaseUrl,
            AppConfig.SupabasePublishableKey,
            new SupabaseOptions
            {
                AutoRefreshToken = true,
                AutoConnectRealtime = false,
                SessionHandler = _store,
            });
    }

    public async Task InitializeAsync() => await _client.InitializeAsync();

    public Task<SignUpOutcome> SignUpDeveloperAsync(
        string email, string password, string displayName, string companyName)
    {
        var data = new Dictionary<string, object>
        {
            ["role"] = "developer",
            ["display_name"] = displayName.Trim(),
            ["company_name"] = companyName.Trim(),
        };

        return SignUpAsync(email, password, data);
    }

    public Task<SignUpOutcome> SignUpTesterAsync(
        string email, string password, string displayName, string region, string devices)
    {
        var deviceList = devices
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(d => d.Length > 0)
            .Take(8)
            .ToArray();

        var data = new Dictionary<string, object>
        {
            ["role"] = "tester",
            ["display_name"] = displayName.Trim(),
            ["region"] = region.Trim(),
            ["devices"] = deviceList,
        };

        return SignUpAsync(email, password, data);
    }

    public async Task RequestPasswordResetAsync(string email)
    {
        var sent = await AuthCallAsync(() => _client.Auth.ResetPasswordForEmail(email.Trim()));
        if (!sent)
        {
            throw new InvalidOperationException("Supabase did not accept that reset request. Try again.");
        }
    }

    public async Task CompletePasswordResetAsync(string email, string token, string newPassword)
    {
        var session = await AuthCallAsync(() => _client.Auth.VerifyOTP(
            email.Trim(),
            token.Trim(),
            Supabase.Gotrue.Constants.EmailOtpType.Recovery));

        if (session is null)
        {
            throw new InvalidOperationException("That reset code is not valid or has expired.");
        }

        await AuthCallAsync(async () =>
        {
            await _client.Auth.Update(new UserAttributes { Password = newPassword });
            return true;
        });

        await SignOutAsync();
    }

    public async Task SignOutAsync()
    {
        try
        {
            await AuthCallAsync(async () =>
            {
                await _client.Auth.SignOut(Supabase.Gotrue.Constants.SignOutScope.Local);
                return true;
            });
        }
        finally
        {
            _store.DestroySession();
        }
    }

    public async Task<Account> WhoAmIAsync()
    {
        WhoAmIDto dto;
        try
        {
            dto = await RpcAsync<WhoAmIDto>("whoami");
        }
        catch (InvalidOperationException ex)
            when (ex.Message.Contains("no TesterLoop profile", StringComparison.OrdinalIgnoreCase))
        {
            await RpcAsync<JsonElement>("claim_profile");
            dto = await RpcAsync<WhoAmIDto>("whoami");
        }

        if (!Enum.TryParse<UserRole>(dto.Role, true, out var role))
        {
            throw new InvalidOperationException($"Unknown account role '{dto.Role}'.");
        }

        return new Account(dto.UserId, dto.DisplayName, dto.Email, role, dto.DeveloperId, dto.TesterId);
    }

    public async Task<DeveloperDashboardDto> GetDeveloperDashboardAsync()
    {
        await RpcAsync<JsonElement>("refresh_campaign_states");
        return await RpcAsync<DeveloperDashboardDto>("developer_dashboard");
    }

    public async Task<TesterDashboardDto> GetTesterDashboardAsync()
    {
        await RpcAsync<JsonElement>("refresh_campaign_states");
        return await RpcAsync<TesterDashboardDto>("tester_dashboard");
    }

    public async Task<AdminDashboardDto> GetAdminDashboardAsync()
    {
        await RpcAsync<JsonElement>("refresh_campaign_states");
        return await RpcAsync<AdminDashboardDto>("admin_dashboard");
    }

    public Task<JsonElement> CreateCampaignAsync(
        string appName, string packageName, Guid paymentPackageId)
        => RpcAsync<JsonElement>("create_campaign", Arguments(
            ("p_app_name", appName.Trim()),
            ("p_package_name", packageName.Trim()),
            ("p_payment_package_id", paymentPackageId)));

    public Task<List<PaymentPackageDto>> ListPaymentPackagesAsync()
        => RpcAsync<List<PaymentPackageDto>>("list_payment_packages");

    public Task<JsonElement> SavePaymentPackageAsync(
        Guid? id, string name, int amountCents, int testerFeeCents, bool isActive)
        => RpcAsync<JsonElement>("save_payment_package", Arguments(
            ("p_id", id),
            ("p_name", name.Trim()),
            ("p_amount_cents", amountCents),
            ("p_tester_fee_cents", testerFeeCents),
            ("p_is_active", isActive)));

    public Task<JsonElement> DeletePaymentPackageAsync(Guid id)
        => RpcAsync<JsonElement>("delete_payment_package", Arguments(
            ("p_id", id)));

    public Task<JsonElement> DeleteCampaignAsync(Guid campaignId)
        => RpcAsync<JsonElement>("delete_campaign", Arguments(
            ("p_campaign_id", campaignId)));

    public Task<JsonElement> AttachGroupAsync(
        Guid campaignId,
        string email,
        string groupName,
        string displayName,
        bool settingsConfirmed)
        => RpcAsync<JsonElement>("attach_group", Arguments(
            ("p_campaign_id", campaignId),
            ("p_group_email", email.Trim()),
            ("p_group_name", groupName.Trim().ToLowerInvariant()),
            ("p_group_display_name", displayName.Trim()),
            ("p_settings_confirmed", settingsConfirmed)));

    public Task<JsonElement> RotateGroupIdentityAsync(Guid campaignId)
        => RpcAsync<JsonElement>("rotate_group_identity", Arguments(
            ("p_campaign_id", campaignId)));

    public Task<AdminProfileDto> UpdateAdminProfileAsync(string displayName, string note)
        => RpcAsync<AdminProfileDto>("update_admin_profile", Arguments(
            ("p_display_name", displayName.Trim()),
            ("p_note", NullIfEmpty(note))));

    public Task<JsonElement> UpdateDeveloperProfileAsync(
        string displayName, string companyName, string contactEmail, string googleEmail)
        => RpcAsync<JsonElement>("update_developer_profile", Arguments(
            ("p_display_name", displayName.Trim()),
            ("p_company_name", companyName.Trim()),
            ("p_contact_email", contactEmail.Trim().ToLowerInvariant()),
            ("p_google_email", googleEmail.Trim().ToLowerInvariant())));

    public Task<JsonElement> UpdateTesterProfileAsync(
        string displayName, string googleEmail, string? region, string[] devices)
        => RpcAsync<JsonElement>("update_tester_profile", Arguments(
            ("p_display_name", displayName.Trim()),
            ("p_google_email", googleEmail.Trim().ToLowerInvariant()),
            ("p_region", NullIfEmpty(region)),
            ("p_devices", devices)));

    public Task<JsonElement> ConfirmPaymentAsync(Guid campaignId, string reference)
        => RpcAsync<JsonElement>("confirm_payment", Arguments(
            ("p_campaign_id", campaignId),
            ("p_reference", NullIfEmpty(reference))));

    public Task<JsonElement> ClaimFreeAccessAsync(Guid campaignId)
        => RpcAsync<JsonElement>("claim_free_access", Arguments(
            ("p_campaign_id", campaignId)));

    public Task<JsonElement> SavePlayLinkAsync(Guid campaignId, string url)
        => RpcAsync<JsonElement>("save_play_link", Arguments(
            ("p_campaign_id", campaignId),
            ("p_url", url.Trim())));

    public Task<JsonElement> SetReportStatusAsync(Guid reportId, string status)
        => RpcAsync<JsonElement>("set_report_status", Arguments(
            ("p_report_id", reportId),
            ("p_status", status)));

    public Task<JoinResultDto> JoinCampaignAsync(Guid campaignId)
        => RpcAsync<JoinResultDto>("join_campaign", Arguments(
            ("p_campaign_id", campaignId)));

    public Task<JsonElement> SetOptInAsync(Guid campaignId, bool optedIn)
        => RpcAsync<JsonElement>("set_opt_in", Arguments(
            ("p_campaign_id", campaignId),
            ("p_opted_in", optedIn)));

    public Task<JsonElement> FileReportAsync(
        Guid campaignId, string severity, string title, string body,
        string buildLabel, string device, string evidenceUrl)
        => RpcAsync<JsonElement>("file_report", Arguments(
            ("p_campaign_id", campaignId),
            ("p_severity", severity),
            ("p_title", title.Trim()),
            ("p_body", body.Trim()),
            ("p_build_label", NullIfEmpty(buildLabel)),
            ("p_device", NullIfEmpty(device)),
            ("p_evidence_url", NullIfEmpty(evidenceUrl))));

    private async Task<SignUpOutcome> SignUpAsync(
        string email, string password, Dictionary<string, object> data)
    {
        await EnsureSchemaAsync();

        var session = await AuthCallAsync(() => _client.Auth.SignUp(
            email.Trim(),
            password,
            new SignUpOptions { Data = data }));

        if (session?.User?.Identities is { Count: 0 })
        {
            await _client.Auth.SignOut(Supabase.Gotrue.Constants.SignOutScope.Local);
            _store.DestroySession();
            throw new InvalidOperationException("An account with that email already exists. Sign in instead.");
        }

        if (session is null || string.IsNullOrWhiteSpace(session.AccessToken))
        {
            throw new InvalidOperationException(
                "The account was created but TesterLoop needs Supabase email confirmation switched off "
                + "to send the activation email. Ask operations to check the authentication settings.");
        }

        if (_client.Auth.CurrentSession is null)
        {
            var refreshToken = session.RefreshToken;
            if (string.IsNullOrWhiteSpace(refreshToken))
            {
                throw new InvalidOperationException("The sign-in session is incomplete. Try signing in again.");
            }

            await AuthCallAsync(async () =>
            {
                await _client.Auth.SetSession(session.AccessToken, refreshToken, true);
                return true;
            });
        }

        try
        {
            await SendActivationAsync();
        }
        finally
        {
            await ClearLocalSessionAsync();
        }

        return new SignUpOutcome(email.Trim());
    }

}
