using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Supabase.Gotrue.Exceptions;

namespace TesterLoop.Desktop.Core.Data;

public sealed partial class SupabaseService
{
    public async Task EnsureSchemaAsync()
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{AppConfig.SupabaseUrl}/rest/v1/rpc/whoami");
        request.Headers.TryAddWithoutValidation("apikey", AppConfig.SupabasePublishableKey);
        request.Content = JsonContent.Create(new Dictionary<string, object?>());

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request);
        }
        catch (HttpRequestException ex)
        {
            throw new InvalidOperationException(
                "Cannot reach Supabase. Check the network connection and try again.", ex);
        }
        catch (TaskCanceledException ex)
        {
            throw new InvalidOperationException(
                "Supabase took too long to respond. Check the network connection and try again.", ex);
        }

        using (response)
        {
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                var body = await response.Content.ReadAsStringAsync();
                throw new InvalidOperationException(ReadError(body, response.StatusCode));
            }

            if ((int)response.StatusCode >= 500)
            {
                throw new InvalidOperationException(
                    "Supabase is not ready. Try again in a moment.");
            }
        }
    }

    private async Task<Supabase.Gotrue.Session> GetSessionAsync()
    {
        var session = _client.Auth.CurrentSession;
        if (session is null)
        {
            throw new InvalidOperationException("Sign in again to continue.");
        }

        if (session.CreatedAt.AddSeconds(session.ExpiresIn) <= DateTime.UtcNow.AddSeconds(30))
        {
            session = await AuthCallAsync(() => _client.Auth.RefreshSession())
                      ?? _client.Auth.CurrentSession;
            if (session is null)
            {
                throw new InvalidOperationException("Your session expired. Sign in again.");
            }
        }

        return session;
    }

    private async Task<T> RpcAsync<T>(string function, Dictionary<string, object?>? arguments = null)
    {
        var session = await GetSessionAsync();

        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{AppConfig.SupabaseUrl}/rest/v1/rpc/{function}");
        request.Headers.TryAddWithoutValidation("apikey", AppConfig.SupabasePublishableKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.AccessToken);
        request.Content = JsonContent.Create(arguments ?? new Dictionary<string, object?>());

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request);
        }
        catch (HttpRequestException ex)
        {
            throw new InvalidOperationException(
                "Cannot reach Supabase. Check the network connection and try again.", ex);
        }
        catch (TaskCanceledException ex)
        {
            throw new InvalidOperationException(
                "Supabase took too long to respond. Check the network connection and try again.", ex);
        }

        using (response)
        {
            var body = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(ReadError(body, response.StatusCode));
            }

            if (string.IsNullOrWhiteSpace(body) || body == "null")
            {
                throw new InvalidOperationException("The server returned no data. Refresh and try again.");
            }

            try
            {
                return JsonSerializer.Deserialize<T>(body, JsonOptions)
                       ?? throw new InvalidOperationException("The server returned an unknown response.");
            }
            catch (JsonException ex)
            {
                throw new InvalidOperationException(
                    "The server returned a response TesterLoop could not read.", ex);
            }
        }
    }

    private static async Task<T> AuthCallAsync<T>(Func<Task<T>> action)
    {
        try
        {
            return await action();
        }
        catch (GotrueException ex)
        {
            throw new InvalidOperationException(AuthMessage(ex), ex);
        }
        catch (HttpRequestException ex)
        {
            throw new InvalidOperationException(
                "Cannot reach Supabase. Check the network connection and try again.", ex);
        }
        catch (TaskCanceledException ex)
        {
            throw new InvalidOperationException(
                "Supabase took too long to respond. Check the network connection and try again.", ex);
        }
    }

    private static string AuthMessage(GotrueException ex)
    {
        return ex.ErrorCode switch
        {
            "invalid_credentials" => "That email and password do not match.",
            "email_not_confirmed" => "Confirm your email address before signing in.",
            "user_already_exists" or "email_exists" => "An account with that email already exists. Sign in instead.",
            "weak_password" => "Choose a stronger password, at least 8 characters.",
            "over_email_send_rate_limit" => "Too many emails have been sent. Wait a minute and try again.",
            "otp_expired" => "That reset code is not valid or has expired.",
            "same_password" => "Choose a password you have not used before.",
            _ => string.IsNullOrWhiteSpace(ex.Message) ? "Supabase rejected the request." : ex.Message,
        };
    }

    private static string ReadError(string body, HttpStatusCode status)
    {
        try
        {
            using var document = JsonDocument.Parse(body);
            var root = document.RootElement;
            if (root.TryGetProperty("code", out var codeElement)
                && codeElement.GetString() is "PGRST202" or "PGRST205")
            {
                return "TesterLoop's database setup is incomplete. Apply the SQL files in "
                       + "Supabase, then reload the API schema and try again.";
            }

            if (root.TryGetProperty("message", out var message)
                && !string.IsNullOrWhiteSpace(message.GetString()))
            {
                return message.GetString()!;
            }

            if (root.TryGetProperty("error", out var error)
                && error.ValueKind == JsonValueKind.String
                && !string.IsNullOrWhiteSpace(error.GetString()))
            {
                return error.GetString()!;
            }
        }
        catch (JsonException)
        {
        }

        return $"Supabase request failed ({(int)status} {status}).";
    }

    private static Dictionary<string, object?> Arguments(params (string Name, object? Value)[] values)
        => values.ToDictionary(v => v.Name, v => v.Value);

    private static string? NullIfEmpty(string? value)
        => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
