namespace TesterLoop.Admin.ViewModels;

public sealed record AdminTesterCampaignRow(
    Guid SeatId,
    Guid CampaignId,
    Guid TesterId,
    string AppName,
    string Developer,
    string StateLabel,
    string SeatLabel,
    string OptInLabel,
    string ReportsLabel,
    string FeeLabel,
    bool Eligible,
    string PayoutState,
    string PayoutLabel,
    string PayoutTone,
    string Reference,
    string PaidLabel,
    string UsageStateLabel,
    string UsageDaysLabel,
    string UsageDetail,
    string UsageTone,
    string UsageTooltip)
{
    public bool CanPay => Eligible && PayoutState != "paid";

    public string ActionLabel => PayoutState == "paid"
        ? "Paid"
        : Eligible ? "Mark paid" : "Not eligible";
}

public sealed record AdminDeveloperCampaignRow(
    string AppName,
    string Package,
    string StateLabel,
    string Tone,
    string PaymentLabel,
    string PaymentTone,
    string OptedLabel,
    string TestersLabel,
    string Created);

public sealed record AdminDeveloperGroupRow(
    string Email,
    string Name,
    string StateLabel,
    string MembersLabel);

public sealed record AdminDeveloperTesterRow(
    string Name,
    string Google,
    string CampaignsLabel,
    string ReportsLabel,
    string DueLabel,
    string PaidLabel);

public sealed record AdminCampaignTesterRow(
    Guid TesterId,
    string Name,
    string Google,
    string Region,
    string SeatLabel,
    string StateLabel,
    string StateTone,
    string OptInLabel,
    string UsageStateLabel,
    string UsageTone,
    string UsageDetail,
    string UsageTooltip,
    string ReportsLabel,
    string PayoutLabel,
    string PayoutTone,
    string Reference,
    string PaidLabel);

public sealed record AdminCampaignReportRow(
    Guid Id,
    string Title,
    string Tester,
    string SeverityLabel,
    string SeverityTone,
    string StatusLabel,
    string StatusTone,
    string Filed,
    string Detail,
    string Preview,
    string Tooltip,
    string Evidence,
    bool HasEvidence,
    string UsageLabel,
    string UsageTone);
