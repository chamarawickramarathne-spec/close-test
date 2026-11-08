using System.Text.RegularExpressions;
using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Desktop.ViewModels;

public sealed partial class DeveloperViewModel
{
    public bool HasCampaigns => Campaigns.Count > 0;

    public bool HasCompletedProjects => CompletedCampaigns.Count > 0;

    public bool HasNoCompletedProjects => CompletedCampaigns.Count == 0;

    public bool HasSelection => _campaign is not null;

    public bool HasGroup => !string.IsNullOrWhiteSpace(_campaign?.GroupEmail);

    public bool HasOptInUrl => !string.IsNullOrWhiteSpace(_campaign?.PlayOptInUrl);

    public bool IsLinkLocked => _campaign is not null
        && (_campaign.HasJoinedTesters || _campaign.Seats.Count > 0);

    public bool CanDeleteProject => _campaign is not null && !_campaign.DeleteLocked;

    public string DeleteLockNote => _campaign is null
        ? string.Empty
        : _campaign.DeleteLocked
            ? $"Locked until {DeleteUnlockLabel(_campaign)}. A tester confirmed opt-in, so this project cannot be edited or deleted until the 14-day run completes."
            : _campaign.State == "passed"
                ? "This project has passed. Deleting it permanently removes its roster and reports."
                : "Deleting this project permanently removes it, its roster and its reports.";

    public bool CanSaveLink => _campaign is
    {
        PaymentState: "paid",
        State: "awaiting_link" or "live" or "at_risk",
    } && !IsLinkLocked;

    public string LinkLockNote => IsLinkLocked
        ? "Locked: a tester has already joined this project, so the closed-test link can no longer be changed."
        : string.Empty;

    public bool ShowsMetrics => _campaign?.State is "live" or "at_risk" or "passed";

    public bool IsPending => _campaign?.State == "pending";

    public bool IsPassed => _campaign?.State == "passed";

    public bool IsCancelled => _campaign?.State == "cancelled";

    public string AppName => _campaign?.AppName ?? "No project selected";

    public string PackageName => _campaign?.PackageName ?? string.Empty;

    public string StatusLabel => _campaign is null ? "—" : StateLabelFor(_campaign);

    public string StatusTone => _campaign is null ? "warn" : Tone(_campaign.State);

    public string Headline => _campaign?.State switch
    {
        "pending" => IsPaymentDue ? "Payment required" : "Group setup in progress",
        "awaiting_link" => IsPaymentDue ? "Payment required" : "One step from live",
        "live" => "Open to testers",
        "at_risk" => "Clock at risk",
        "passed" => "Play requirement met",
        "cancelled" => "Not running",
        _ => "No project selected",
    };

    public string NextStepTitle => _campaign?.State switch
    {
        "pending" => IsPaymentDue ? "Pay the project fee" : "Group setup in progress",
        "awaiting_link" => IsPaymentDue ? "Pay the project fee" : "Attach the group in Play Console",
        "live" => "Testers can join now",
        "at_risk" => "Keep 12 testers opted in",
        "passed" => "Nothing to do",
        "cancelled" => "This project is stopped",
        _ => "Create your first project",
    };

    public string NextStepBody => _campaign is null
        ? "Add a project to start a closed test. Operations will create the Google Group by hand and attach its address."
        : _campaign.State switch
        {
            "pending" => IsPaymentDue
                ? $"Pay the {PaymentAmountLabel} project fee with the online button on the fee card, or quote {PaymentReferenceLabel}. Operations records it, creates the matching Google Group and attaches it here. You can then add the group to Play Console and save the testing link."
                : $"Your payment is recorded. Operations is creating the Google Group for {_campaign.AppName} with the reserved group number and will attach it here. You do not need to do anything yet.",
            "awaiting_link" => IsPaymentDue
                ? $"Your group is attached. Pay the {PaymentAmountLabel} project fee with the online button on the fee card, or quote {PaymentReferenceLabel}. Once the payment lands you can paste the group address into Play Console and save the testing link."
                : $"In Play Console, open the closed test for {_campaign.PackageName} and paste the group address into the tester list. Then save the testing link below.",
            "live" =>
                "Testers can join from their bench and open the Play link to install. Keep 12 of them opted in for 14 continuous days.",
            "at_risk" =>
                "Fewer than 12 testers are opted in. Ask your testers to opt back in; each restart adds 14 days from that point.",
            "passed" => "The 12-tester, 14-day requirement is met for this project.",
            "cancelled" => "This project was stopped, so it is hidden from testers.",
            _ => "Save a Play testing link so testers can join.",
        };

    public string GroupEmail => string.IsNullOrWhiteSpace(_campaign?.GroupEmail)
        ? "Not attached yet"
        : _campaign.GroupEmail;

    public string GroupStateLabel
    {
        get
        {
            if (string.IsNullOrWhiteSpace(_campaign?.GroupEmail))
            {
                return _campaign?.PaymentState == "paid"
                    ? "Payment recorded. Operations is creating the group."
                    : "Pay the project fee online to start group setup";
            }

            var label = "Manual group · no API sync";
            return _campaign.GroupAttachedAt is null
                ? label
                : $"{label} · attached {_campaign.GroupAttachedAt:dd MMM yyyy}";
        }
    }

    public string OptInUrl => _campaign?.PlayOptInUrl ?? string.Empty;

    public string OptedInLabel => _campaign is null
        ? "—"
        : $"{_campaign.OptedIn} / {_campaign.RequiredTesters}";

    public string DaysLabel => _campaign is null ? "—" : $"{_campaign.DaysBanked} d";

    public string StartedLabel => _campaign?.ClockStartedAt is null
        ? "Not started"
        : $"{_campaign.ClockStartedAt:dd MMM yyyy}";

    public string SeatsLabel => _campaign is null ? "—" : $"{_campaign.SeatsUsed} / {AppConfig.SeatCap}";

    public string SpareLabel => _campaign is null
        ? "—"
        : $"{SeatsOpen} seat{(SeatsOpen == 1 ? string.Empty : "s")} open - {_campaign.TestersUsed} / {AppConfig.SeatCap} paid";

    public string SeatSummary => _campaign is null
        ? "No testers in this project"
        : $"{_campaign.SeatsUsed} active seat{(_campaign.SeatsUsed == 1 ? string.Empty : "s")} - {_campaign.TestersUsed} paid of {AppConfig.SeatCap}";

    private int SeatsOpen => Math.Max(0, AppConfig.SeatCap - (_campaign?.SeatsUsed ?? 0));

    public string RequirementText =>
        $"{_campaign?.RequiredTesters ?? 12} testers must stay opted in for {AppConfig.RequiredDays} continuous days. " +
        $"A project may use at most {AppConfig.SeatCap} testers in total, because each tester is paid. " +
        "A dropped seat can only be reused by the same tester.";

    public string ReportsLabel => $"{Reports.Count} report{(Reports.Count == 1 ? string.Empty : "s")}";

    public string ProjectCountLabel => $"{Campaigns.Count} project{(Campaigns.Count == 1 ? string.Empty : "s")}";

    public string CompletedCountLabel => $"{CompletedCampaigns.Count} completed";

    public string EligibleLabel => _campaign?.EligibleOn is null
        ? "Not eligible yet"
        : $"Eligible {_campaign.EligibleOn:dd MMM yyyy}";

    private void LoadDetail()
    {
        ResetCheckoutState();
        SeatCells.Clear();
        Roster.Clear();
        Reports.Clear();

        for (var number = 1; number <= AppConfig.SeatCap; number++)
        {
            var seat = _campaign?.Seats.FirstOrDefault(s => s.SeatNumber == number);
            var state = seat?.State switch
            {
                "opted_in" => "opted",
                "joined" => "joined",
                _ => "empty",
            };

            var label = seat?.State == "opted_in" ? "Opted in" : seat?.State == "joined" ? "Joined" : "Empty";
            SeatCells.Add(new SeatCell(number, state, label));
        }

        if (_campaign is null)
        {
            return;
        }

        foreach (var seat in _campaign.Seats
                     .Where(s => s.State is "opted_in" or "joined")
                     .OrderBy(s => s.SeatNumber))
        {
            var name = string.IsNullOrWhiteSpace(seat.TesterName) ? $"Tester {seat.SeatNumber}" : seat.TesterName;
            Roster.Add(new RosterRow(
                name,
                Initials(name),
                seat.Devices.FirstOrDefault() ?? "—",
                seat.SeatNumber,
                seat.State == "opted_in" ? "Opted in" : "Joined",
                seat.HasReport ? "Reported" : "No report",
                seat.HasReport ? "good" : "muted",
                seat.OptedInAt is null ? "—" : $"{seat.OptedInAt:dd MMM}",
                seat.State == "opted_in" ? "good" : "warn"));
        }

        foreach (var report in _campaign.Reports.OrderByDescending(r => r.CreatedAt))
        {
            Reports.Add(new ReportRow(
                report.Id,
                report.Title,
                report.Body,
                report.Severity,
                SeverityTone(report.Severity),
                StatusLabelForReport(report.Status),
                report.TesterName,
                Ago(report.CreatedAt),
                report.BuildLabel ?? "—",
                report.Device ?? "—",
                report.EvidenceUrl ?? string.Empty));
        }
    }

    private static string DeleteUnlockLabel(DeveloperCampaignDto campaign)
        => campaign.DeleteUnlocksAt is null
            ? "the 14-day run completes"
            : $"{campaign.DeleteUnlocksAt:dd MMM yyyy}";

    private static string Initials(string name)
    {
        var parts = name.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length switch
        {
            0 => "?",
            1 => parts[0][..1].ToUpperInvariant(),
            _ => (parts[0][..1] + parts[^1][..1]).ToUpperInvariant(),
        };
    }

    private static string Ago(DateTime at)
    {
        var span = DateTime.Now - at;
        return span.TotalHours < 24 ? $"{(int)span.TotalHours} h ago" : $"{(int)span.TotalDays} d ago";
    }

    private static string SeverityTone(string severity) => severity switch
    {
        "blocker" => "bad",
        "major" => "warn",
        _ => "muted",
    };

    private static string StatusLabelForReport(string status) => status switch
    {
        "open" => "Open",
        "triaged" => "Triaged",
        "fixed" => "Fixed",
        "closed" => "Closed",
        _ => status,
    };

    private static bool IsPackageName(string value)
    {
        if (value.Length < 3 || value.Contains(' ') || value.StartsWith('.') || value.EndsWith('.'))
        {
            return false;
        }

        var parts = value.Split('.');
        return parts.Length >= 2
               && parts.All(p => p.Length > 0
                                 && char.IsLetter(p[0])
                                 && Regex.IsMatch(p, "^[A-Za-z][A-Za-z0-9_]*$"));
    }

    private static string StateLabelFor(DeveloperCampaignDto campaign)
    {
        if (campaign.State == "awaiting_link" && campaign.PaymentState != "paid")
        {
            return "Payment due";
        }

        return StateLabel(campaign.State);
    }

    private static string StateLabel(string state) => state switch
    {
        "pending" => "Pending group",
        "awaiting_link" => "Needs Play link",
        "live" => "Live",
        "at_risk" => "At risk",
        "passed" => "Passed",
        "cancelled" => "Cancelled",
        _ => state,
    };

    private static string Tone(string state) => state switch
    {
        "live" or "passed" => "good",
        "at_risk" or "cancelled" => "bad",
        _ => "warn",
    };
}
