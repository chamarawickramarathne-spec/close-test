using System.Globalization;
using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private Guid? _packageId;
    private string _packageName = string.Empty;
    private string _packageAmount = "15.00";
    private string _packageTesterFee = "0.50";
    private bool _packageActive = true;
    private bool _isPackageEditorOpen;
    private string _packageError = string.Empty;

    public AsyncRelayCommand SavePackageCommand { get; }

    public RelayCommand NewPackageCommand { get; }

    public AsyncRelayCommand<PaymentPackageRow> EditPackageCommand { get; }

    public RelayCommand ClosePackageCommand { get; }

    public bool HasPackages => Packages.Count > 0;

    public string PackageCountLabel => Packages.Count == 1 ? "1 package" : $"{Packages.Count} packages";

    public bool IsPackageEditorOpen
    {
        get => _isPackageEditorOpen;
        private set => Set(ref _isPackageEditorOpen, value);
    }

    public string PackageEditorTitle => _packageId is null ? "New package" : "Edit package";

    public string PackageName
    {
        get => _packageName;
        set => Set(ref _packageName, value);
    }

    public string PackageAmount
    {
        get => _packageAmount;
        set
        {
            if (Set(ref _packageAmount, value))
            {
                PackageError = string.Empty;
            }
        }
    }

    public string PackageTesterFee
    {
        get => _packageTesterFee;
        set
        {
            if (Set(ref _packageTesterFee, value))
            {
                PackageError = string.Empty;
            }
        }
    }

    public bool PackageActive
    {
        get => _packageActive;
        set => Set(ref _packageActive, value);
    }

    public string PackageError
    {
        get => _packageError;
        private set
        {
            if (Set(ref _packageError, value))
            {
                Raise(nameof(HasPackageError));
            }
        }
    }

    public bool HasPackageError => PackageError.Length > 0;

    private void LoadPackages(AdminDashboardDto dashboard)
    {
        Packages.Clear();

        if (dashboard.Packages is not null)
        {
            foreach (var package in dashboard.Packages)
            {
                Packages.Add(new PaymentPackageRow(
                    package.Id,
                    package.Name,
                    Money(package.AmountCents),
                    Money(package.TesterFeeCents),
                    package.CampaignsUsed,
                    package.CampaignsUsed == 1 ? "1 project" : $"{package.CampaignsUsed} projects",
                    package.IsActive ? "Active" : "Inactive",
                    package.IsActive ? "good" : "bad",
                    package.IsActive,
                    package.AmountCents,
                    package.TesterFeeCents));
            }
        }

        Raise(nameof(HasPackages));
        Raise(nameof(PackageCountLabel));
    }

    private void StartNewPackage()
    {
        _packageId = null;
        PackageName = string.Empty;
        PackageAmount = "15.00";
        PackageTesterFee = "0.50";
        PackageActive = true;
        PackageError = string.Empty;
        ClearPackageDeleteState();
        Raise(nameof(PackageEditorTitle));
        IsPackageEditorOpen = true;
    }

    private Task EditPackageAsync(PaymentPackageRow? row)
    {
        if (row is null)
        {
            return Task.CompletedTask;
        }

        _packageId = row.Id;
        PackageName = row.Name;
        PackageAmount = (row.AmountCents / 100m).ToString("0.00", CultureInfo.InvariantCulture);
        PackageTesterFee = (row.TesterFeeCents / 100m).ToString("0.00", CultureInfo.InvariantCulture);
        PackageActive = row.IsActive;
        PackageError = string.Empty;
        RefreshPackageDeleteState(row.CampaignsUsed, row.IsActive);
        Raise(nameof(PackageEditorTitle));
        IsPackageEditorOpen = true;
        return Task.CompletedTask;
    }

    private void ClosePackage()
    {
        IsPackageEditorOpen = false;
        PackageError = string.Empty;
        _packageId = null;
        ClearPackageDeleteState();
    }

    private async Task SavePackageAsync()
    {
        PackageError = string.Empty;

        var name = PackageName.Trim();
        if (name.Length < 2)
        {
            PackageError = "Enter a package name with at least 2 characters.";
            return;
        }

        if (name.Length > 80)
        {
            PackageError = "Keep the package name to 80 characters or fewer.";
            return;
        }

        if (!TryParseMoney(PackageAmount, out var amountCents))
        {
            PackageError = "Enter a project fee such as 15 or 15.00.";
            return;
        }

        if (!TryParseMoney(PackageTesterFee, out var testerFeeCents))
        {
            PackageError = "Enter a tester payout such as 0.50.";
            return;
        }

        try
        {
            await _service.SavePaymentPackageAsync(
                _packageId, name, amountCents, testerFeeCents, PackageActive);
            ClosePackage();
            Toast = $"Saved package {name}.";
            await LoadAsync();
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            PackageError = ex.Message;
        }
    }

    private static bool TryParseMoney(string text, out int cents)
    {
        cents = 0;
        var cleaned = text.Replace("$", string.Empty).Replace(",", string.Empty).Trim();

        if (!decimal.TryParse(
                cleaned,
                NumberStyles.Number,
                CultureInfo.InvariantCulture,
                out var amount))
        {
            return false;
        }

        var value = amount * 100m;
        if (value != decimal.Truncate(value) || value < 1m || value > 1_000_000m)
        {
            return false;
        }

        cents = (int)value;
        return true;
    }
}
