namespace TesterLoop.Admin.ViewModels;

public sealed partial class AdminViewModel
{
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

    private static string GroupLabel(string state) => state switch
    {
        "manual" => "Manual",
        "orphaned" => "Orphaned",
        "revoked" => "Revoked",
        _ => state,
    };

    private static string GroupTone(string state) => state switch
    {
        "orphaned" => "bad",
        "revoked" => "muted",
        _ => "warn",
    };

    private static string SeatLabel(string state) => state switch
    {
        "joined" => "Joined",
        "opted_in" => "Opted in",
        "dropped" => "Dropped",
        _ => state,
    };
}
