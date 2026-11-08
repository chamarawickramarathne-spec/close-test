using System.Net.Http;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private string _profileDisplayName = string.Empty;
    private string _profileEmail = string.Empty;
    private string _profileNote = string.Empty;
    private string _profileToast = string.Empty;
    private string _profileError = string.Empty;

    public AsyncRelayCommand SaveProfileCommand { get; }

    public event Action<string>? ProfileSaved;

    public string ProfileDisplayName
    {
        get => _profileDisplayName;
        set
        {
            if (Set(ref _profileDisplayName, value))
            {
                ClearProfileMessages();
            }
        }
    }

    public string ProfileEmail
    {
        get => _profileEmail;
        private set => Set(ref _profileEmail, value);
    }

    public string ProfileNote
    {
        get => _profileNote;
        set
        {
            if (Set(ref _profileNote, value))
            {
                ClearProfileMessages();
            }
        }
    }

    public string ProfileToast
    {
        get => _profileToast;
        private set
        {
            if (Set(ref _profileToast, value))
            {
                Raise(nameof(HasProfileToast));
            }
        }
    }

    public bool HasProfileToast => ProfileToast.Length > 0;

    public string ProfileError
    {
        get => _profileError;
        private set
        {
            if (Set(ref _profileError, value))
            {
                Raise(nameof(HasProfileError));
            }
        }
    }

    public bool HasProfileError => ProfileError.Length > 0;

    internal void ApplyProfile(AdminProfileDto? profile)
    {
        if (profile is null)
        {
            return;
        }

        _profileDisplayName = profile.DisplayName;
        _profileEmail = profile.Email;
        _profileNote = profile.Note ?? string.Empty;
        Raise(nameof(ProfileDisplayName));
        Raise(nameof(ProfileEmail));
        Raise(nameof(ProfileNote));
    }

    private async Task SaveProfileAsync()
    {
        ProfileError = string.Empty;
        ProfileToast = string.Empty;

        var displayName = ProfileDisplayName.Trim();
        if (displayName.Length < 2 || displayName.Length > 120)
        {
            ProfileError = "Enter a display name between 2 and 120 characters.";
            return;
        }

        var note = ProfileNote.Trim();
        if (note.Length > 500)
        {
            ProfileError = "Keep the admin note under 500 characters.";
            return;
        }

        try
        {
            var profile = await _service.UpdateAdminProfileAsync(displayName, note);
            ApplyProfile(profile);
            ProfileToast = "Profile saved.";
            ProfileSaved?.Invoke(ProfileDisplayName);
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            ProfileError = ex.Message;
        }
    }

    private void ClearProfileMessages()
    {
        if (_profileToast.Length > 0)
        {
            _profileToast = string.Empty;
            Raise(nameof(ProfileToast));
            Raise(nameof(HasProfileToast));
        }

        if (_profileError.Length > 0)
        {
            _profileError = string.Empty;
            Raise(nameof(ProfileError));
            Raise(nameof(HasProfileError));
        }
    }
}
