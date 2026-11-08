using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private PaymentRow? _selectedPayment;
    private string _paymentReference = string.Empty;

    public AsyncRelayCommand ConfirmPaymentCommand { get; }

    public PaymentRow? SelectedPayment
    {
        get => _selectedPayment;
        set
        {
            if (Set(ref _selectedPayment, value))
            {
                Raise(nameof(HasSelectedPayment));
                Raise(nameof(SelectedPaymentLabel));
                Raise(nameof(ConfirmPaymentLabel));
            }
        }
    }

    public bool HasSelectedPayment => SelectedPayment is not null;

    public string SelectedPaymentLabel => SelectedPayment is null
        ? "Select a project to record its payment"
        : $"{SelectedPayment.AppName} - {SelectedPayment.Developer} - {SelectedPayment.Amount} - {SelectedPayment.Reference}";

    public string ConfirmPaymentLabel => SelectedPayment is null
        ? "Confirm payment"
        : $"Confirm {SelectedPayment.Amount} payment";

    public bool HasPayments => Payments.Count > 0;

    public string PaymentCountLabel => Payments.Count == 1 ? "1 payment due" : $"{Payments.Count} payments due";

    public string PaymentReference
    {
        get => _paymentReference;
        set => Set(ref _paymentReference, value);
    }

    private void LoadPayments(AdminDashboardDto dashboard)
    {
        var keepPayment = SelectedPayment?.Id;
        Payments.Clear();
        foreach (var payment in dashboard.Payments ?? [])
        {
            Payments.Add(new PaymentRow(
                payment.CampaignId,
                payment.AppName,
                payment.Developer,
                payment.PackageName,
                $"${payment.AmountCents / 100m:0}",
                string.IsNullOrWhiteSpace(payment.GroupEmail) ? "No group" : payment.GroupEmail,
                ReferenceFor(payment.CampaignId),
                Ago(payment.GroupAttachedAt ?? payment.CreatedAt)));
        }

        SelectedPayment = Payments.FirstOrDefault(p => p.Id == keepPayment)
                          ?? Payments.FirstOrDefault();
        PaymentReference = string.Empty;
        Raise(nameof(HasPayments));
        Raise(nameof(PaymentCountLabel));
    }

    private async Task ConfirmPaymentAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;

        if (SelectedPayment is null)
        {
            Error = "Select a project from the payments queue first.";
            return;
        }

        try
        {
            var payment = SelectedPayment;
            await _service.ConfirmPaymentAsync(payment.Id, PaymentReference);
            PaymentReference = string.Empty;
            await LoadAsync();

            var project = GroupSetup.FirstOrDefault(p => p.Id == payment.Id);
            if (project is not null)
            {
                SelectedGroupSetup = project;
            }

            Toast = $"Payment recorded for {payment.AppName}. A group number is reserved. "
                    + "Use Open create page with the reserved address and display name, confirm all five settings, then attach the group.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private static string ReferenceFor(Guid campaignId)
        => $"TL-{campaignId.ToString("N")[..8].ToUpperInvariant()}";

    private static string PaymentLabel(string? state, int amountCents)
        => state == "paid" ? "Paid" : $"{Money(amountCents)} due";

    private static string PaymentTone(string? state) => state == "paid" ? "good" : "warn";

    private static string PaymentMethod(AdminCampaignProfileDto campaign)
        => campaign.PaymentPaidVia switch
        {
            "online" => string.IsNullOrWhiteSpace(campaign.PaymentProviderRef)
                ? "Paid online via Lemon Squeezy"
                : $"Paid online via Lemon Squeezy - order {campaign.PaymentProviderRef}",
            "manual" => "Recorded by operations",
            _ => campaign.PaymentState == "paid" ? "Paid - method not recorded" : "Not paid yet",
        };
}
