using TesterLoop.Desktop.Core;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class DeveloperViewModel
{
    public bool ShowsPayment => _campaign is not null && _campaign.State is not "cancelled";

    public bool IsPaymentDue => _campaign is
    {
        PaymentState: not "paid",
        State: "pending" or "awaiting_link",
    };

    public string PaymentAmountLabel => _campaign is null
        ? AppConfig.ProjectFeeLabel
        : $"${_campaign.PaymentAmountCents / 100m:0}";

    public string PaymentStateLabel => _campaign is null
        ? "No project selected"
        : _campaign.PaymentState == "paid"
            ? _campaign.PaidAt is null ? "Paid" : $"Paid {_campaign.PaidAt:dd MMM yyyy}"
            : _campaign.GroupEmail is null
                ? $"{PaymentAmountLabel} due before group setup"
                : $"{PaymentAmountLabel} due";

    public string PaymentReferenceLabel => _campaign is null
        ? string.Empty
        : $"Reference TL-{_campaign.Id.ToString("N")[..8].ToUpperInvariant()}";

    public string PaymentInstruction => _campaign?.PaymentState == "paid"
        ? _campaign?.GroupEmail is null
            ? "Payment recorded. Operations is creating the Google Group. You can save the Play link once it is attached."
            : "The project fee is recorded. You can save the Play link once the group is attached in Play Console."
        : _campaign?.GroupEmail is null
            ? $"Pay {PaymentAmountLabel} online below, or quote the reference above so operations can record it. Operations then creates and attaches the Google Group."
            : $"Pay {PaymentAmountLabel} online below, or quote the reference above. Operations confirms it, then you can save the Play link.";

    public string PaymentTone => _campaign?.PaymentState == "paid" ? "good" : "warn";
}
