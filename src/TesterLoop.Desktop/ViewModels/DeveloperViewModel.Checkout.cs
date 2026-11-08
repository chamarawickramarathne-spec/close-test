using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class DeveloperViewModel
{
    private CancellationTokenSource? _paymentWatch;
    private string _payNote = string.Empty;

    public bool CanPayOnline => IsPaymentDue;

    public bool ShowsPaymentMethod => _campaign?.PaymentState == "paid";

    public string PaymentMethodLabel => _campaign?.PaymentPaidVia switch
    {
        "online" => "Paid online",
        "manual" => "Recorded by operations",
        _ => _campaign?.PaymentState == "paid" ? "Paid" : string.Empty,
    };

    public string ProviderReferenceLabel => string.IsNullOrWhiteSpace(_campaign?.PaymentProviderRef)
        ? string.Empty
        : $"Lemon Squeezy order {_campaign.PaymentProviderRef}";

    public bool HasProviderReference => ProviderReferenceLabel.Length > 0;

    public string PayButtonLabel => $"Pay {PaymentAmountLabel} online";

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

    public AsyncRelayCommand PayOnlineCommand { get; }

    public AsyncRelayCommand CheckPaymentCommand { get; }

    private void ResetCheckoutState()
    {
        StopPaymentWatch();
        PayNote = string.Empty;
    }

    private async Task PayOnlineAsync()
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
            Error = "This project fee does not need an online payment.";
            return;
        }

        try
        {
            var checkout = await _service.StartOnlinePaymentAsync(_campaign.Id);

            if (!LinkLauncher.TryOpenCheckout(checkout.CheckoutUrl))
            {
                Error = "The checkout link could not be opened. Ask operations to record the fee instead.";
                return;
            }

            PayNote = $"Checkout opened in your browser. This page updates when the payment lands. "
                      + $"Quote {PaymentReferenceLabel} if you pay another way.";
            StartPaymentWatch(_campaign.Id);
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private async Task CheckPaymentAsync()
    {
        Error = string.Empty;

        if (_campaign is null)
        {
            return;
        }

        var campaignId = _campaign.Id;
        await LoadAsync();

        var current = _allCampaigns.FirstOrDefault(c => c.Id == campaignId);
        if (current is null)
        {
            return;
        }

        if (current.PaymentState == "paid")
        {
            StopPaymentWatch();
            PayNote = string.Empty;
            Toast = "Payment received. Operations is creating the Google Group.";
        }
        else
        {
            PayNote = "No payment has arrived yet. If you just paid, give it a minute and check again.";
        }
    }

    private void StartPaymentWatch(Guid campaignId)
    {
        StopPaymentWatch();

        var watch = new CancellationTokenSource();
        _paymentWatch = watch;
        _ = WatchPaymentAsync(campaignId, watch.Token);
    }

    private void StopPaymentWatch()
    {
        var watch = _paymentWatch;
        _paymentWatch = null;
        if (watch is null)
        {
            return;
        }

        try
        {
            watch.Cancel();
        }
        catch (ObjectDisposedException)
        {
        }

        watch.Dispose();
    }

    private async Task WatchPaymentAsync(Guid campaignId, CancellationToken token)
    {
        try
        {
            for (var attempt = 0; attempt < 120; attempt++)
            {
                await Task.Delay(TimeSpan.FromSeconds(5), token);

                var dashboard = await _service.GetDeveloperDashboardAsync();
                var campaign = dashboard.Campaigns.FirstOrDefault(c => c.Id == campaignId);
                if (campaign is null)
                {
                    return;
                }

                if (campaign.PaymentState == "paid")
                {
                    await LoadAsync();
                    Toast = "Payment received. Operations is creating the Google Group.";
                    return;
                }
            }

            if (!token.IsCancellationRequested)
            {
                PayNote = "Still waiting for the payment. Press Check payment status after the checkout finishes.";
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
        }
    }
}
