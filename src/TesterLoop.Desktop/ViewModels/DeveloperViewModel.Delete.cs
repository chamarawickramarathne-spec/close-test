using System.Net.Http;
using TesterLoop.Desktop.Core;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class DeveloperViewModel
{
    public AsyncRelayCommand DeleteProjectCommand { get; }

    public AsyncRelayCommand<CampaignOption> DeleteCompletedCommand { get; }

    private async Task DeleteProjectAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;

        if (_campaign is null)
        {
            Error = "Select a project first.";
            return;
        }

        if (_campaign.DeleteLocked)
        {
            Error = DeleteLockNote;
            return;
        }

        var campaign = _campaign;
        if (!await ConfirmDeleteAsync(campaign.AppName))
        {
            return;
        }

        try
        {
            await _service.DeleteCampaignAsync(campaign.Id);
            _campaign = null;
            _selected = null;
            await LoadAsync();
            Toast = $"Deleted {campaign.AppName}.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private async Task DeleteCompletedAsync(CampaignOption option)
    {
        Error = string.Empty;
        Toast = string.Empty;

        if (!option.CanDelete)
        {
            Error = option.DeleteNote;
            return;
        }

        if (!await ConfirmDeleteAsync(option.AppName))
        {
            return;
        }

        try
        {
            await _service.DeleteCampaignAsync(option.Id);
            if (_campaign?.Id == option.Id)
            {
                _campaign = null;
                _selected = null;
            }

            await LoadAsync();
            Toast = $"Deleted {option.AppName}.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private Task<bool> ConfirmDeleteAsync(string appName)
        => _notifications.ConfirmAsync(
            "Delete project",
            $"Delete {appName}? This removes its seats, roster and reports permanently.",
            "Delete");
}
