using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class TesterViewModel
{
    private string _profileName = string.Empty;
    private string _profileGoogleEmail = string.Empty;
    private string _profileRegion = string.Empty;
    private string[] _savedDevices = [];
    private string _savedName = string.Empty;
    private string _savedGoogleEmail = string.Empty;
    private string _savedRegion = string.Empty;
    private RelayCommand? _resetProfileCommand;
    private AsyncRelayCommand? _saveProfileCommand;

    public RelayCommand ResetProfileCommand => _resetProfileCommand ??= new RelayCommand(ResetProfile);

    public AsyncRelayCommand SaveProfileCommand => _saveProfileCommand ??= new AsyncRelayCommand(SaveProfileAsync);

    public string ProfileName
    {
        get => _profileName;
        set => Set(ref _profileName, value);
    }

    public string ProfileGoogleEmail
    {
        get => _profileGoogleEmail;
        set => Set(ref _profileGoogleEmail, value);
    }

    public string ProfileRegion
    {
        get => _profileRegion;
        set => Set(ref _profileRegion, value);
    }

    private void LoadProfile(TesterDto tester)
    {
        _savedName = tester.DisplayName;
        _savedGoogleEmail = tester.GoogleEmail;
        _savedRegion = tester.Region ?? string.Empty;
        _savedDevices = tester.Devices.ToArray();
        ResetProfileFields();
    }

    private void ResetProfile()
    {
        Error = string.Empty;
        Toast = string.Empty;
        ResetProfileFields();
    }

    private void ResetProfileFields()
    {
        ProfileName = _savedName;
        ProfileGoogleEmail = _savedGoogleEmail;
        ProfileRegion = _savedRegion;
    }

    private async Task SaveProfileAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;

        var name = ProfileName.Trim();
        if (name.Length < 2 || name.Length > 120)
        {
            Error = "Display name must be between 2 and 120 characters.";
            return;
        }

        if (!InputChecks.LooksLikeEmail(ProfileGoogleEmail))
        {
            Error = "Enter a valid Google account email address.";
            return;
        }

        var region = ProfileRegion.Trim();
        if (region.Length > 120)
        {
            Error = "Keep the region under 120 characters.";
            return;
        }

        try
        {
            await _service.UpdateTesterProfileAsync(
                name, ProfileGoogleEmail, region, _savedDevices);
            _savedName = name;
            _savedGoogleEmail = ProfileGoogleEmail.Trim().ToLowerInvariant();
            _savedRegion = region;
            await LoadAsync();
            Toast = "Profile saved.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }
}
