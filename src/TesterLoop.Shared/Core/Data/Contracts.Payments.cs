using System.Text.Json.Serialization;

namespace TesterLoop.Desktop.Core.Data;

public sealed record PaymentCheckoutDto(
    [property: JsonPropertyName("checkout_url")] string CheckoutUrl,
    [property: JsonPropertyName("intent_id")] Guid IntentId,
    [property: JsonPropertyName("expires_at")] DateTime? ExpiresAt,
    [property: JsonPropertyName("amount_cents")] int AmountCents,
    [property: JsonPropertyName("currency")] string Currency);
