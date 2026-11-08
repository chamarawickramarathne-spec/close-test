using System.Text.RegularExpressions;

namespace TesterLoop.Desktop.Core;

public static partial class InputChecks
{
    public static bool LooksLikeEmail(string value)
        => value.Trim().Length > 0 && EmailPattern().IsMatch(value.Trim());

    public static string[] SplitDevices(string value)
        => value.Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(device => device.Trim())
            .Where(device => device.Length > 0)
            .ToArray();

    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$")]
    private static partial Regex EmailPattern();
}
