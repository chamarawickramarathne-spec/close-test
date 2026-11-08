using System.Net.Http;
using TesterLoop.Desktop.Core;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class TesterViewModel
{
    private async Task JoinAsync(AvailableRow row)
    {
        Error = string.Empty;
        Toast = string.Empty;

        if (!row.CanJoin)
        {
            Error = "This project has no tester seats left. Refresh to see the latest projects.";
            return;
        }

        try
        {
            await _service.JoinCampaignAsync(row.CampaignId);
            await LoadAsync();

            if (LinkLauncher.TryOpenGroup(row.GroupName))
            {
                Toast = $"You joined {row.AppName}. The Google Group opened so you can request access.";
                return;
            }

            Toast = $"You joined {row.AppName}. Ask operations for the Google Group link.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private async Task SetOptInAsync(TesterCampaignRow row)
    {
        Error = string.Empty;
        Toast = string.Empty;

        var message = row.IsOptedIn
            ? "Opting out frees your seat and removes your opted-in days from this project."
            : "Leaving this project frees your seat. Confirm opt-in only in the TesterLoop mobile app.";

        var accepted = await _notifications.ConfirmAsync("Leave project", message, "Leave");
        if (!accepted)
        {
            return;
        }

        try
        {
            var campaignId = row.CampaignId;
            var appName = row.AppName;
            await _service.SetOptInAsync(campaignId, false);
            Mine.Remove(row);
            Raise(string.Empty);
            await LoadAsync();
            Toast = $"You left {appName}. Your seat is free. Confirm opt-in in the TesterLoop mobile app.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private void OpenGroup(TesterCampaignRow? row)
    {
        Error = string.Empty;

        if (row is null || !LinkLauncher.TryOpenGroup(row.GroupName))
        {
            Error = "This project has no Google Group link yet.";
            return;
        }

        Toast = "Opened the Google Group in your browser.";
    }

    private void OpenLink(TesterCampaignRow? row)
    {
        Error = string.Empty;

        if (row is null || string.IsNullOrWhiteSpace(row.TestUrl))
        {
            Error = "The developer has not saved a testing link yet.";
            return;
        }

        if (!LinkLauncher.TryOpen(row.TestUrl))
        {
            Error = "Could not open the browser from that testing link.";
            return;
        }

        Toast = "Opened the testing link in your browser.";
    }

    private async Task FileReportAsync()
    {
        Error = string.Empty;
        Toast = string.Empty;

        if (SelectedReportCampaign is null)
        {
            Error = "Join a project before filing a report.";
            return;
        }

        if (ReportTitle.Trim().Length < 4)
        {
            Error = "Give the report a title of at least four characters.";
            return;
        }

        if (string.IsNullOrWhiteSpace(ReportBody))
        {
            Error = "Describe what happened.";
            return;
        }

        if (!string.IsNullOrWhiteSpace(ReportEvidence)
            && !ReportEvidence.Trim().StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            Error = "Evidence links must use https://.";
            return;
        }

        try
        {
            await _service.FileReportAsync(
                SelectedReportCampaign.CampaignId,
                SelectedSeverity.Value,
                ReportTitle,
                ReportBody,
                ReportBuild,
                ReportDevice,
                ReportEvidence);

            var app = SelectedReportCampaign.AppName;
            ReportTitle = string.Empty;
            ReportBody = string.Empty;
            ReportBuild = string.Empty;
            ReportEvidence = string.Empty;
            await LoadAsync();
            Toast = $"Report filed against {app}.";
        }
        catch (Exception ex) when (ex is InvalidOperationException or HttpRequestException)
        {
            Error = ex.Message;
        }
    }

    private static string SeverityLabel(string value) => value switch
    {
        "blocker" => "Blocker",
        "major" => "Major",
        "minor" => "Minor",
        "cosmetic" => "Cosmetic",
        _ => value,
    };

    private static string SeverityTone(string value) => value switch
    {
        "blocker" => "bad",
        "major" => "warn",
        _ => "muted",
    };

    private static string ReportStatus(string value) => value switch
    {
        "open" => "Open",
        "triaged" => "Triaged",
        "fixed" => "Fixed",
        "closed" => "Closed",
        _ => value,
    };

    private static string Ago(DateTime at)
    {
        var span = DateTime.Now - at;
        return span.TotalHours < 24 ? $"{(int)span.TotalHours} h ago" : $"{(int)span.TotalDays} d ago";
    }
}
