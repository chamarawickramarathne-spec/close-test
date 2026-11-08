namespace TesterLoop.Desktop.ViewModels;

public sealed record CampaignOption(
    Guid Id,
    string AppName,
    string PackageName,
    string StateLabel,
    string Tone,
    string SeatsLabel,
    string TestersLabel,
    bool CanDelete,
    string DeleteNote);

public sealed record SeatCell(int Number, string State, string Label);

public sealed record RosterRow(
    string Name,
    string Initials,
    string Device,
    int Seat,
    string StateLabel,
    string Reported,
    string ReportTone,
    string Opted,
    string Tone);

public sealed record ReportRow(
    Guid Id,
    string Title,
    string Body,
    string SeverityLabel,
    string SeverityTone,
    string StatusLabel,
    string Tester,
    string When,
    string Build,
    string Device,
    string Evidence);

public sealed record SeverityOption(string Value, string Label);

public sealed record TesterCampaignRow(
    Guid CampaignId,
    string AppName,
    string GroupEmail,
    string GroupName,
    string StatusLabel,
    string Tone,
    string DaysIn,
    string SeatNo,
    string TestUrl,
    string OptInLabel,
    bool IsOptedIn,
    string VerificationNote);

public sealed record AvailableRow(
    Guid CampaignId,
    string AppName,
    string Package,
    int SeatsFree,
    string SeatsLeft,
    string Requirement,
    string GroupEmail,
    string GroupName)
{
    public bool CanJoin => SeatsFree > 0;
}

public sealed record TesterReportRow(
    Guid Id,
    string AppName,
    string SeverityLabel,
    string StatusLabel,
    string Title,
    string Tone,
    string When,
    string Usage);
