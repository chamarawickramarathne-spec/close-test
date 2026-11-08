namespace TesterLoop.Desktop.Core;

/// <summary>
/// Validates the Google Play links a campaign may store. Both closed-test links
/// (/apps/testing/...) and store details links (/store/apps/details?id=...) are
/// accepted; anything else is refused before it reaches the database or browser.
/// </summary>
public static class PlayLink
{
    private const string TestingPath = "/apps/testing/";
    private const string StoreDetailsPath = "/store/apps/details";

    public static bool IsValid(string? url) => TryCreate(url, out _);

    public static bool TryCreate(string? url, out Uri uri)
    {
        uri = null!;
        if (string.IsNullOrWhiteSpace(url))
        {
            return false;
        }

        var candidate = url.Trim();
        if (candidate.Length > 500
            || !Uri.TryCreate(candidate, UriKind.Absolute, out var parsed)
            || parsed.Scheme != Uri.UriSchemeHttps
            || parsed.Port != 443
            || parsed.UserInfo.Length > 0
            || !parsed.Host.Equals("play.google.com", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var path = parsed.AbsolutePath;
        if (path.StartsWith(TestingPath, StringComparison.OrdinalIgnoreCase))
        {
            if (!IsPackageId(path[TestingPath.Length..]))
            {
                return false;
            }
        }
        else if (!path.Equals(StoreDetailsPath, StringComparison.OrdinalIgnoreCase)
                 || !IsPackageId(QueryValue(parsed, "id")))
        {
            return false;
        }

        uri = parsed;
        return true;
    }

    private static bool IsPackageId(string value)
    {
        if (value.Length == 0)
        {
            return false;
        }

        foreach (var c in value)
        {
            if (!char.IsAsciiLetterOrDigit(c) && c is not ('.' or '_' or '-'))
            {
                return false;
            }
        }

        return true;
    }

    private static string QueryValue(Uri uri, string key)
    {
        foreach (var pair in uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = pair.Split('=', 2);
            if (parts.Length == 2
                && parts[0].Equals(key, StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    return Uri.UnescapeDataString(parts[1]);
                }
                catch (UriFormatException)
                {
                    return string.Empty;
                }
            }
        }

        return string.Empty;
    }
}
