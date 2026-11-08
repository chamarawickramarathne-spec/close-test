namespace TesterLoop.Admin.ViewModels;

public sealed record PaymentPackageRow(
    Guid Id,
    string Name,
    string AmountLabel,
    string TesterFeeLabel,
    int CampaignsUsed,
    string CampaignsLabel,
    string StatusLabel,
    string Tone,
    bool IsActive,
    int AmountCents,
    int TesterFeeCents);

public sealed record GroupSetupRow(
    Guid Id,
    string AppName,
    string Developer,
    string Package,
    string ReservedEmail,
    string ReservedUrlName,
    string ReservedDisplayName,
    string SequenceLabel,
    string Age);

public sealed record PaymentRow(
    Guid Id,
    string AppName,
    string Developer,
    string Package,
    string Amount,
    string GroupEmail,
    string Reference,
    string Age);

public sealed record GroupRow(
    string Email,
    string Name,
    string DisplayName,
    string Developer,
    string Members,
    string SettingsLabel,
    string StateLabel,
    string Tone);

public sealed record AdminCampaignRow(
    Guid Id,
    string AppName,
    string Developer,
    string Package,
    string StateLabel,
    string Tone,
    string PaymentLabel,
    string PaymentTone,
    string OptedLabel,
    string SeatsLabel);

public sealed record DeveloperRow(
    Guid Id,
    string Company,
    string Contact,
    string Google,
    string CampaignsLabel,
    string Created);

public sealed record TesterRow(
    Guid Id,
    string Name,
    string Email,
    string Google,
    string Region,
    string Reliability,
    string Joined,
    string StateLabel,
    string Tone);

public sealed record FeedbackRow(
    Guid Id,
    string AppName,
    string Developer,
    string Tester,
    string Title,
    string Severity,
    string SeverityTone,
    string Status,
    string StatusTone,
    string Age);

public sealed record AuditRow(
    DateTime At,
    string When,
    string Actor,
    string Action,
    string Target);
