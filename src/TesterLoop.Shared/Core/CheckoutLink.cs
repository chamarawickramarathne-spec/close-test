namespace TesterLoop.Desktop.Core;

public static class CheckoutLink
{
    private const string Host = ".lemonsqueezy.com";

    public static bool TryCreate(string? url, out Uri uri)
    {
        uri = null!;

        var value = url?.Trim();
        if (string.IsNullOrEmpty(value) || value.Length > 1000)
        {
            return false;
        }

        if (!Uri.TryCreate(value, UriKind.Absolute, out var candidate))
        {
            return false;
        }

        if (candidate.Scheme != Uri.UriSchemeHttps)
        {
            return false;
        }

        if (!candidate.Host.EndsWith(Host, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (candidate.UserInfo.Length > 0 || !candidate.IsDefaultPort)
        {
            return false;
        }

        if (!candidate.AbsolutePath.StartsWith("/checkout/", StringComparison.Ordinal))
        {
            return false;
        }

        uri = candidate;
        return true;
    }
}
