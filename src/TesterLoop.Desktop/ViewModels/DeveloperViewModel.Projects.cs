using System.Net.Http;
using TesterLoop.Desktop.Core;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class DeveloperViewModel
{
    private async Task LoadPackagesAsync()
    {
        PackageError = string.Empty;

        try
        {
            var packages = await _service.ListPaymentPackagesAsync();
            var keep = SelectedPackage?.Id;

            Packages.Clear();
            foreach (var package in packages)
            {
                Packages.Add(package);
            }

            SelectedPackage = Packages.FirstOrDefault(p => p.Id == keep)
                ?? Packages.FirstOrDefault();
            Raise(nameof(HasPackages));
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Packages.Clear();
            SelectedPackage = null;
            PackageError = "Payment packages could not be loaded. Run "
                           + "sql/migrations/026_payment_packages.sql in Supabase, then refresh. ("
                           + ex.Message + ")";
            Raise(nameof(HasPackages));
        }
    }

    private async Task CreateProjectAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;

        var name = NewAppName.Trim();
        if (name.Length < 2)
        {
            Error = "Give the app a name of at least two characters.";
            return;
        }

        var package = NewPackage.Trim();
        if (!IsPackageName(package))
        {
            Error = "Package name must look like com.company.app, with letters, digits, dots and underscores.";
            return;
        }

        var selected = SelectedPackage;
        if (selected is null)
        {
            Error = Packages.Count == 0
                ? "No payment package is available yet. Ask operations to create one."
                : "Choose a payment package.";
            return;
        }

        var feeLabel = "$" + (selected.AmountCents / 100m)
            .ToString("0.00", System.Globalization.CultureInfo.InvariantCulture);

        try
        {
            await _service.CreateCampaignAsync(name, package, selected.Id);
            NewAppName = string.Empty;
            NewPackage = string.Empty;
            _campaign = null;
            await LoadAsync();
            Toast = $"Project submitted with the {selected.Name} package. Pay the {feeLabel} project fee online, or quote the reference on the project page. Operations creates the Google Group and attaches it here.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }
}
