namespace TesterLoop.Desktop.Core;

/// <summary>
/// Builds the Google Groups web address from a group's URL name. The name is
/// the slug shown in groups.google.com/g/&lt;name&gt;, and it is stored on the
/// campaign group beside the group address because the two can differ.
/// </summary>
public static class GroupLink
{
    private const string BaseUrl = "https://groups.google.com/g/";

    public static bool IsValid(string? groupName) => TryCreate(groupName, out _);

    public static bool TryCreate(string? groupName, out Uri uri)
    {
        uri = null!;
        if (string.IsNullOrWhiteSpace(groupName))
        {
            return false;
        }

        var slug = groupName.Trim().ToLowerInvariant();
        if (slug.Length > 200
            || slug[0] is '.' or '-' or '_'
            || slug[^1] is '.' or '-' or '_'
            || !slug.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-'))
        {
            return false;
        }

        uri = new Uri(BaseUrl + slug, UriKind.Absolute);
        return true;
    }
}
