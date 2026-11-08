using System.Net.Http;
using System.Runtime.InteropServices;
using System.Windows;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private GroupSetupRow? _selectedGroupSetup;
    private string _groupUrlName = string.Empty;
    private bool _groupSettingsConfirmed;

    public AsyncRelayCommand AttachGroupCommand { get; }

    public AsyncRelayCommand RotateGroupCommand { get; }

    public RelayCommand CopyReservedEmailCommand { get; }

    public RelayCommand CopyReservedDisplayCommand { get; }

    public RelayCommand OpenGroupsCommand { get; }

    public RelayCommand OpenGroupCreateCommand { get; }

    public RelayCommand CopyReservedUrlNameCommand { get; }

    public GroupSetupRow? SelectedGroupSetup
    {
        get => _selectedGroupSetup;
        set
        {
            if (!Set(ref _selectedGroupSetup, value))
            {
                return;
            }

            GroupUrlName = value?.ReservedUrlName ?? string.Empty;
            GroupSettingsConfirmed = false;
            Raise(nameof(HasSelectedGroupSetup));
            Raise(nameof(SelectedGroupSetupLabel));
            Raise(nameof(CanAttachGroup));
            Raise(nameof(CanRotateGroup));
            Raise(nameof(ReservedGroupPageLabel));
        }
    }

    public bool HasSelectedGroupSetup => SelectedGroupSetup is not null;

    public bool HasGroupSetup => GroupSetup.Count > 0;

    public string GroupSetupCountLabel => GroupSetup.Count == 1
        ? "1 group ready to create"
        : $"{GroupSetup.Count} groups ready to create";

    public string SelectedGroupSetupLabel => SelectedGroupSetup is null
        ? "Select a project after recording its payment"
        : $"{SelectedGroupSetup.AppName} - {SelectedGroupSetup.ReservedDisplayName}";

    public string GroupUrlName
    {
        get => _groupUrlName;
        set
        {
            if (Set(ref _groupUrlName, value))
            {
                Raise(nameof(CanAttachGroup));
                Raise(nameof(ReservedGroupPageLabel));
            }
        }
    }

    public bool GroupSettingsConfirmed
    {
        get => _groupSettingsConfirmed;
        set
        {
            if (Set(ref _groupSettingsConfirmed, value))
            {
                Raise(nameof(CanAttachGroup));
            }
        }
    }

    public bool CanAttachGroup
        => SelectedGroupSetup is not null
           && GroupSettingsConfirmed
           && GroupLink.IsValid(GroupUrlName);

    public bool CanRotateGroup => SelectedGroupSetup is not null;

    public string ReservedGroupPageLabel => string.IsNullOrWhiteSpace(GroupUrlName)
        ? "groups.google.com/g/"
        : $"groups.google.com/g/{GroupUrlName}";

    private void LoadGroupSetup(AdminDashboardDto dashboard)
    {
        var keep = SelectedGroupSetup?.Id;
        GroupSetup.Clear();

        foreach (var project in dashboard.GroupSetup ?? [])
        {
            GroupSetup.Add(new GroupSetupRow(
                project.CampaignId,
                project.AppName,
                project.Developer,
                project.PackageName,
                project.ReservedGroupEmail,
                project.ReservedGroupUrlName,
                project.ReservedGroupDisplayName,
                $"#{project.GroupSequence:000}",
                Ago(project.GroupIdentityReservedAt)));
        }

        SelectedGroupSetup = GroupSetup.FirstOrDefault(p => p.Id == keep)
                             ?? GroupSetup.FirstOrDefault();
        Raise(nameof(HasGroupSetup));
        Raise(nameof(GroupSetupCountLabel));
    }

    private async Task AttachGroupAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;

        if (SelectedGroupSetup is null)
        {
            Error = "Select a project from the group setup queue first.";
            return;
        }

        if (!GroupSettingsConfirmed)
        {
            Error = "Confirm that all five Google Group settings match before attaching the group.";
            return;
        }

        if (!GroupLink.IsValid(GroupUrlName))
        {
            Error = "Enter the actual group URL name from groups.google.com/g/. "
                    + "Use lowercase letters, numbers, dots, underscores or hyphens.";
            return;
        }

        try
        {
            var project = SelectedGroupSetup;
            await _service.AttachGroupAsync(
                project.Id,
                project.ReservedEmail,
                GroupUrlName,
                project.ReservedDisplayName,
                true);

            await LoadAsync();
            Toast = $"Group {project.ReservedEmail} attached to {project.AppName}. The developer can now save the Play link.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private async Task RotateGroupAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;

        if (SelectedGroupSetup is null)
        {
            Error = "Select a project from the group setup queue first.";
            return;
        }

        var project = SelectedGroupSetup;
        var accepted = await _notifications.ConfirmAsync(
            "Issue next group number",
            $"Issue the next available group number for {project.AppName}? Use this only when Google says the reserved address or name is already taken.",
            "Issue number");

        if (!accepted)
        {
            return;
        }

        try
        {
            var result = await _service.RotateGroupIdentityAsync(project.Id);
            await LoadAsync();
            var email = result.TryGetProperty("reserved_group_email", out var emailValue)
                ? emailValue.GetString()
                : null;
            Toast = string.IsNullOrWhiteSpace(email)
                ? $"A new group number was issued for {project.AppName}."
                : $"New group identity: {email}";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private void CopyReservedEmail()
    {
        if (SelectedGroupSetup is null)
        {
            return;
        }

        CopyText(SelectedGroupSetup.ReservedEmail, "Group address copied.");
    }

    private void CopyReservedDisplay()
    {
        if (SelectedGroupSetup is null)
        {
            return;
        }

        CopyText(SelectedGroupSetup.ReservedDisplayName, "Group display name copied.");
    }

    private void OpenGroups() => LinkLauncher.TryOpenGroupsHome();

    private void OpenGroupCreate()
    {
        Error = string.Empty;
        if (!LinkLauncher.TryOpenGroupCreate())
        {
            Error = "Could not open the Google Groups create page.";
        }
    }

    private void CopyReservedUrlName()
    {
        if (SelectedGroupSetup is null)
        {
            return;
        }

        var name = string.IsNullOrWhiteSpace(GroupUrlName)
            ? SelectedGroupSetup.ReservedUrlName
            : GroupUrlName;
        CopyText(name, "Group URL name copied.");
    }

    private void CopyText(string value, string message)
    {
        try
        {
            Clipboard.SetText(value);
            Toast = message;
        }
        catch (Exception ex) when (ex is ExternalException or InvalidOperationException)
        {
            Error = "The clipboard is busy. Press Ctrl+C after selecting the text.";
        }
    }
}
