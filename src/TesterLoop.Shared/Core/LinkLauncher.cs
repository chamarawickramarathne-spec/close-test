using System.Diagnostics;

namespace TesterLoop.Desktop.Core;

public static class LinkLauncher
{
    private const string GroupsHome = "https://groups.google.com/";
    private const string GroupsCreate = "https://groups.google.com/g/create";

    public static bool TryOpen(string url)
    {
        if (!PlayLink.TryCreate(url, out var uri))
        {
            return false;
        }

        return TryStart(uri);
    }

    public static bool TryOpenGroup(string groupName)
    {
        if (!GroupLink.TryCreate(groupName, out var uri))
        {
            return false;
        }

        return TryStart(uri);
    }

    public static bool TryOpenGroupsHome() => TryStart(new Uri(GroupsHome, UriKind.Absolute));

    public static bool TryOpenGroupCreate() => TryStart(new Uri(GroupsCreate, UriKind.Absolute));

    public static bool TryOpenCheckout(string? url)
    {
        if (!CheckoutLink.TryCreate(url, out var uri))
        {
            return false;
        }

        return TryStart(uri);
    }

    private static bool TryStart(Uri uri)
    {
        try
        {
            Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
            return true;
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            return false;
        }
    }
}
