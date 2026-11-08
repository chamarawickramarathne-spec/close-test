using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class DeveloperViewModel
{
    private string _profileName = string.Empty;
    private string _profileCompany = string.Empty;
    private string _profileContactEmail = string.Empty;
    private string _profileGoogleEmail = string.Empty;
    private string _savedName = string.Empty;
    private string _savedCompany = string.Empty;
    private string _savedContactEmail = string.Empty;
    private string _savedGoogleEmail = string.Empty;
    private RelayCommand? _resetProfileCommand;
    private AsyncRelayCommand? _saveProfileCommand;

    public RelayCommand ResetProfileCommand => _resetProfileCommand ??= new RelayCommand(ResetProfile);

    public AsyncRelayCommand SaveProfileCommand => _saveProfileCommand ??= new AsyncRelayCommand(SaveProfileAsync);

    public string ProfileName
    {
        get => _profileName;
        set => Set(ref _profileName, value);
    }

    public string ProfileCompany
    {
        get => _profileCompany;
        set => Set(ref _profileCompany, value);
    }

    public string ProfileContactEmail
    {
        get => _profileContactEmail;
        set => Set(ref _profileContactEmail, value);
    }

    public string ProfileGoogleEmail
    {
        get => _profileGoogleEmail;
        set => Set(ref _profileGoogleEmail, value);
    }

    private void LoadProfile(DeveloperDto developer)
    {
        _savedName = developer.DisplayName;
        _savedCompany = developer.CompanyName;
        _savedContactEmail = developer.ContactEmail;
        _savedGoogleEmail = developer.GoogleEmail;
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
        ProfileCompany = _savedCompany;
        ProfileContactEmail = _savedContactEmail;
        ProfileGoogleEmail = _savedGoogleEmail;
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

        var company = ProfileCompany.Trim();
        if (company.Length < 2 || company.Length > 120)
        {
            Error = "Company name must be between 2 and 120 characters.";
            return;
        }

        if (!InputChecks.LooksLikeEmail(ProfileContactEmail))
        {
            Error = "Enter a valid contact email address.";
            return;
        }

        if (!InputChecks.LooksLikeEmail(ProfileGoogleEmail))
        {
            Error = "Enter a valid Google account email address.";
            return;
        }

        try
        {
            await _service.UpdateDeveloperProfileAsync(
                name, company, ProfileContactEmail, ProfileGoogleEmail);
            _savedName = name;
            _savedCompany = company;
            _savedContactEmail = ProfileContactEmail.Trim().ToLowerInvariant();
            _savedGoogleEmail = ProfileGoogleEmail.Trim().ToLowerInvariant();
            await LoadAsync();
            Toast = "Profile saved.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }
}
