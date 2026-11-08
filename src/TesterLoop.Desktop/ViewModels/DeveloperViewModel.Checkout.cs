using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class DeveloperViewModel
{
    private string _payNote = string.Empty;

    public bool CanClaimFreeAccess => IsPaymentDue;

    public bool ShowsPaymentMethod => _campaign?.PaymentState == "paid";

    public string PaymentMethodLabel => _campaign?.PaymentPaidVia switch
    {
        "free" => "Free access",
        "online" => "Paid online",
        "manual" => "Recorded by operations",
        _ => _campaign?.PaymentState == "paid" ? "Paid" : string.Empty,
    };

    public string ProviderReferenceLabel => string.IsNullOrWhiteSpace(_campaign?.PaymentProviderRef)
        ? string.Empty
        : $"Lemon Squeezy order {_campaign.PaymentProviderRef}";

    public bool HasProviderReference => ProviderReferenceLabel.Length > 0;

    public string FreeAccessButtonLabel => "Free Access";

    public string PayNote
    {
        get => _payNote;
        private set
        {
            if (Set(ref _payNote, value))
            {
                Raise(nameof(HasPayNote));
            }
        }
    }

    public bool HasPayNote => PayNote.Length > 0;

    public AsyncRelayCommand FreeAccessCommand { get; }

    private void ResetCheckoutState()
    {
        PayNote = string.Empty;
    }

    private async Task ClaimFreeAccessAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;
        PayNote = string.Empty;

        if (_campaign is null)
        {
            Error = "Select a project first.";
            return;
        }

        if (!IsPaymentDue)
        {
            Error = "This project does not need activation.";
            return;
        }

        try
        {
            await _service.ClaimFreeAccessAsync(_campaign.Id);
            await LoadAsync();
            Toast = "Free access activated. Operations is creating the Google Group.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }
}
