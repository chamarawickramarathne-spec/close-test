using System.Collections.ObjectModel;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    public ObservableCollection<DeveloperRow> Developers { get; } = [];

    public ObservableCollection<TesterRow> Testers { get; } = [];

    public ObservableCollection<FeedbackRow> Feedbacks { get; } = [];

    public string CampaignTabLabel => Campaigns.Count == 1 ? "1 close test project" : $"{Campaigns.Count} close test projects";

    public string DeveloperTabLabel => Developers.Count == 1 ? "1 developer" : $"{Developers.Count} developers";

    public string TesterTabLabel => Testers.Count == 1 ? "1 tester" : $"{Testers.Count} testers";

    public string FeedbackTabLabel => Feedbacks.Count == 1 ? "1 feedback" : $"{Feedbacks.Count} feedback";

    public bool HasCampaigns => Campaigns.Count > 0;

    public bool HasDevelopers => Developers.Count > 0;

    public bool HasTesters => Testers.Count > 0;

    public bool HasFeedback => Feedbacks.Count > 0;

    internal void LoadTabs(AdminDashboardDto dashboard)
    {
        Developers.Clear();
        foreach (var developer in dashboard.Developers ?? [])
        {
            Developers.Add(new DeveloperRow(
                developer.Id,
                developer.CompanyName,
                developer.ContactEmail,
                developer.GoogleEmail,
                $"{developer.CampaignCount} total / {developer.LiveCount} live",
                developer.CreatedAt.ToString("yyyy-MM-dd")));
        }

        Testers.Clear();
        foreach (var tester in dashboard.Testers ?? [])
        {
            Testers.Add(new TesterRow(
                tester.Id,
                tester.DisplayName,
                tester.Email ?? "-",
                tester.GoogleEmail,
                string.IsNullOrWhiteSpace(tester.Region) ? "No region" : tester.Region,
                tester.Reliability.ToString("0.0"),
                tester.JoinedCount == 1 ? "1 project" : $"{tester.JoinedCount} projects",
                tester.IsActive ? "Active" : "Inactive",
                tester.IsActive ? "good" : "muted"));
        }

        Feedbacks.Clear();
        foreach (var feedback in dashboard.Feedback ?? [])
        {
            Feedbacks.Add(new FeedbackRow(
                feedback.Id,
                feedback.AppName,
                feedback.Developer,
                feedback.Tester,
                feedback.Title,
                Label(feedback.Severity),
                SeverityTone(feedback.Severity),
                Label(feedback.Status),
                StatusTone(feedback.Status),
                Ago(feedback.CreatedAt)));
        }

        Raise(nameof(CampaignTabLabel));
        Raise(nameof(DeveloperTabLabel));
        Raise(nameof(TesterTabLabel));
        Raise(nameof(FeedbackTabLabel));
        Raise(nameof(HasCampaigns));
        Raise(nameof(HasDevelopers));
        Raise(nameof(HasTesters));
        Raise(nameof(HasFeedback));

        ApplyProfile(dashboard.Profile);
    }

    private static string Label(string value)
        => value.Length == 0 ? value : char.ToUpperInvariant(value[0]) + value[1..];

    private static string SeverityTone(string severity) => severity switch
    {
        "blocker" => "bad",
        "major" => "warn",
        _ => "muted",
    };

    private static string StatusTone(string status) => status switch
    {
        "fixed" or "closed" => "good",
        "open" or "triaged" => "warn",
        _ => "muted",
    };
}
