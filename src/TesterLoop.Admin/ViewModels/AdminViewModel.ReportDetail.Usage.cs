using TesterLoop.Desktop.Core;
using TesterLoop.Desktop.Core.Data;

namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
    private static ReportUsageLabels BuildReportUsage(
        AdminTesterUsageDto? usage,
        bool snapshot)
    {
        if (usage is null)
        {
            return snapshot
                ? new ReportUsageLabels(
                    "Not captured",
                    "muted",
                    "No snapshot",
                    "This report was filed before usage snapshots were enabled.")
                : new ReportUsageLabels(
                    "Not reported",
                    "muted",
                    "No data",
                    "No install or usage data has been reported for this project.");
        }

        if (!usage.Available)
        {
            return snapshot
                ? new ReportUsageLabels(
                    "Not reported",
                    "muted",
                    "No data",
                    "No install or usage data had been reported when this report was filed.")
                : new ReportUsageLabels(
                    "Not reported",
                    "muted",
                    "No data",
                    "No install or usage data has been reported for this project.");
        }

        var state = usage.MeetsUsageRequirement
            ? "Met"
            : usage.Installed
                ? "In progress"
                : "Not installed";
        var tone = usage.MeetsUsageRequirement
            ? "good"
            : usage.Installed ? "warn" : "muted";
        var days = $"{usage.ContinuousDaysUsed}/{AppConfig.RequiredDays} days";
        var lastUsed = usage.LastUsageAt is null
            ? "no usage yet"
            : $"last used {usage.LastUsageAt:yyyy-MM-dd}";
        var detail = $"Installed: {(usage.Installed ? "yes" : "no")} - "
                     + $"{usage.DistinctDaysUsed} distinct days - {lastUsed}";

        return new ReportUsageLabels(state, tone, days, detail);
    }

    private static (string Text, string Tone) CompareUsage(
        AdminTesterUsageDto? snapshot,
        AdminTesterUsageDto? current)
    {
        if (snapshot is null)
        {
            return ("No usage was captured with this report. Live usage is shown for context.", "muted");
        }

        if (current is null)
        {
            return ("The tester has not reported live usage for this project.", "muted");
        }

        var same = snapshot.Installed == current.Installed
                   && snapshot.DistinctDaysUsed == current.DistinctDaysUsed
                   && snapshot.ContinuousDaysUsed == current.ContinuousDaysUsed
                   && snapshot.MeetsUsageRequirement == current.MeetsUsageRequirement;

        return same
            ? ("Live usage matches the snapshot taken when this report was filed.", "good")
            : ("Live usage has changed since this report was filed.", "warn");
    }

    private static ReportInstallLabels BuildInstallHistory(AdminReportDetailDto dto)
    {
        var history = dto.InstallHistory;
        if (history is null || history.Count == 0)
        {
            return new ReportInstallLabels(
                "Not captured",
                "muted",
                "No daily install checks were stored with this report.",
                "This report predates daily install history.");
        }

        var checkedDays = history.Count(day => day.Checked);
        var installedDays = history.Count(day => day.Checked && day.Installed == true);
        var missingDays = history.Count(day => day.Checked && day.Installed == false);

        var state = checkedDays == 0
            ? "Not checked"
            : missingDays == 0
                ? "Installed daily"
                : installedDays == 0
                    ? "Not installed"
                    : "Gaps found";
        var tone = checkedDays == 0
            ? "muted"
            : missingDays == 0
                ? "good"
                : installedDays == 0
                    ? "bad"
                    : "warn";

        var summary = checkedDays == 0
            ? $"{history.Count} days in window, none checked"
            : $"{installedDays} of {checkedDays} checked days installed";

        var window = dto.InstallWindowStart is null || dto.InstallWindowEnd is null
            ? string.Empty
            : $"Window {dto.InstallWindowStart.Value:yyyy-MM-dd} to {dto.InstallWindowEnd.Value:yyyy-MM-dd}";
        var captured = dto.InstallHistoryCapturedAt is null
            ? "Not captured"
            : $"Captured {dto.InstallHistoryCapturedAt:yyyy-MM-dd HH:mm}";
        var footer = window.Length == 0 ? captured : $"{window} - {captured}";

        return new ReportInstallLabels(state, tone, summary, footer);
    }

    private sealed record ReportUsageLabels(
        string State,
        string Tone,
        string Days,
        string Detail);

    private sealed record ReportInstallLabels(
        string State,
        string Tone,
        string Summary,
        string Footer);
}
