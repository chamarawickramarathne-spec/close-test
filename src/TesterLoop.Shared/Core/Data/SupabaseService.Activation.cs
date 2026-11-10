using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Supabase.Gotrue.Exceptions;

namespace TesterLoop.Desktop.Core.Data;

public sealed partial class SupabaseService
{
    public async Task SendActivationAsync()
    {
        var session = await GetSessionAsync();

        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{AppConfig.SupabaseUrl}/functions/v1/send-activation");
        request.Headers.TryAddWithoutValidation("apikey", AppConfig.SupabasePublishableKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.AccessToken);
        request.Content = JsonContent.Create(new Dictionary<string, object?>());

        await SendActivationRequestAsync(request);
    }

    public async Task RequestActivationAsync(string email)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{AppConfig.SupabaseUrl}/functions/v1/send-activation");
        request.Headers.TryAddWithoutValidation("apikey", AppConfig.SupabasePublishableKey);
        request.Content = JsonContent.Create(new { email = email.Trim() });

        await SendActivationRequestAsync(request);
    }

    private async Task SendActivationRequestAsync(HttpRequestMessage request)
    {
        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request);
        }
        catch (HttpRequestException ex)
        {
            throw new InvalidOperationException(
                "Cannot reach the activation service. Check the network connection and try again.", ex);
        }
        catch (TaskCanceledException ex)
        {
            throw new InvalidOperationException(
                "The activation service took too long to respond. Try again in a moment.", ex);
        }

        using (response)
        {
            var body = await response.Content.ReadAsStringAsync();

            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                throw new InvalidOperationException(
                    "Account activation is not deployed yet. Ask operations to finish setup.");
            }

            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                throw new InvalidOperationException("Your session expired. Sign in again.");
            }

            if (response.StatusCode == HttpStatusCode.TooManyRequests)
            {
                throw new InvalidOperationException(
                    "Please wait a minute before requesting another activation email.");
            }

            if ((int)response.StatusCode >= 500)
            {
                throw new InvalidOperationException(
                    "The activation email could not be sent. Try again in a minute.");
            }

            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(ReadError(body, response.StatusCode));
            }
        }
    }

    public Task AbandonSessionAsync() => ClearLocalSessionAsync();

    private async Task ClearLocalSessionAsync()
    {
        try
        {
            await _client.Auth.SignOut(Supabase.Gotrue.Constants.SignOutScope.Local);
        }
        catch (Exception ex) when (ex is GotrueException or HttpRequestException or TaskCanceledException)
        {
            // A remote sign-out failure must not hide an account that was created and emailed.
        }
        finally
        {
            _store.DestroySession();
        }
    }
}
