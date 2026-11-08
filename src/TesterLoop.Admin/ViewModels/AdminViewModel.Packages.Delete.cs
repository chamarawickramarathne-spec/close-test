using System.Net.Http;
using TesterLoop.Desktop.Core;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private int _packageCampaignsUsed;
    private bool _packageIsLastActive;

    public AsyncRelayCommand DeletePackageCommand { get; }

    public bool IsExistingPackage => _packageId is not null;

    public bool CanDeletePackage => _packageId is not null
                                    && _packageCampaignsUsed == 0
                                    && !_packageIsLastActive;

    public string DeletePackageNote
    {
        get
        {
            if (_packageCampaignsUsed == 1)
            {
                return "Used by 1 project. Deactivate it instead so project history stays intact.";
            }

            if (_packageCampaignsUsed > 1)
            {
                return $"Used by {_packageCampaignsUsed} projects. Deactivate it instead so project history stays intact.";
            }

            if (_packageIsLastActive)
            {
                return "Keep at least one active payment package.";
            }

            return "Permanently removes this unused package.";
        }
    }

    private void RefreshPackageDeleteState(int campaignsUsed, bool wasActive)
    {
        _packageCampaignsUsed = campaignsUsed;
        _packageIsLastActive = wasActive
                               && !Packages.Any(p => p.Id != _packageId && p.IsActive);
        RaiseDeleteState();
    }

    private void ClearPackageDeleteState()
    {
        _packageCampaignsUsed = 0;
        _packageIsLastActive = false;
        RaiseDeleteState();
    }

    private void RaiseDeleteState()
    {
        Raise(nameof(IsExistingPackage));
        Raise(nameof(CanDeletePackage));
        Raise(nameof(DeletePackageNote));
    }

    private async Task DeletePackageAsync()
    {
        if (_packageId is null)
        {
            return;
        }

        var name = PackageName.Trim();

        if (!CanDeletePackage)
        {
            PackageError = DeletePackageNote;
            return;
        }

        var confirmed = await _notifications.ConfirmAsync(
            "Delete payment package?",
            $"Delete {name}? This cannot be undone. Projects that already used a package keep their copied fee and payout.",
            "Delete package",
            "Keep package");

        if (!confirmed)
        {
            return;
        }

        PackageError = string.Empty;

        try
        {
            await _service.DeletePaymentPackageAsync(_packageId.Value);
            ClosePackage();
            Toast = $"Deleted package {name}.";
            await LoadAsync();
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            PackageError = ex.Message;
        }
    }
}
