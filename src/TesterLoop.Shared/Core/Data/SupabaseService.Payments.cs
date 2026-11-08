using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace TesterLoop.Desktop.Core.Data;

public sealed partial class SupabaseService
{
    public async Task<PaymentCheckoutDto> StartOnlinePaymentAsync(Guid campaignId)
    {
        var session = await GetSessionAsync();

        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{AppConfig.SupabaseUrl}/functions/v1/create-payment");
        request.Headers.TryAddWithoutValidation("apikey", AppConfig.SupabasePublishableKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.AccessToken);
        request.Content = JsonContent.Create(new { campaign_id = campaignId });

        HttpResponseMessage response;
        try
        {
            response = await _http.SendAsync(request);
        }
        catch (HttpRequestException ex)
        {
            throw new InvalidOperationException(
                "Cannot reach the payment service. Check the network connection and try again.", ex);
        }
        catch (TaskCanceledException ex)
        {
            throw new InvalidOperationException(
                "The payment service took too long to respond. Try again in a moment.", ex);
        }

        using (response)
        {
            var body = await response.Content.ReadAsStringAsync();

            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                throw new InvalidOperationException(
                    "Online payment is not deployed yet. Ask operations to record the fee.");
            }

            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                throw new InvalidOperationException("Your session expired. Sign in again.");
            }

            if (!response.IsSuccessStatusCode)
            {
                throw new InvalidOperationException(ReadError(body, response.StatusCode));
            }

            try
            {
                return JsonSerializer.Deserialize<PaymentCheckoutDto>(body, JsonOptions)
                       ?? throw new InvalidOperationException(
                           "The payment service returned an unknown response.");
            }
            catch (JsonException ex)
            {
                throw new InvalidOperationException(
                    "The payment service returned a response TesterLoop could not read.", ex);
            }
        }
    }
}
