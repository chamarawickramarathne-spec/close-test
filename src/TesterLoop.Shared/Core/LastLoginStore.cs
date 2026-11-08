using System.IO;

namespace TesterLoop.Desktop.Core;

public static class LastLoginStore
{
    public const string MainApp = "main";
    public const string AdminApp = "admin";

    public static string? Load(string appKey)
    {
        var path = PathFor(appKey);
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }

            var email = File.ReadAllText(path).Trim();
            return email.Length is > 0 and <= 254 ? email : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    public static void Save(string appKey, string email)
    {
        var value = email.Trim().ToLowerInvariant();
        if (value.Length == 0 || value.Length > 254)
        {
            return;
        }

        try
        {
            var path = PathFor(appKey);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, value);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Remembering the last email is a convenience; sign-in still works.
        }
    }

    private static string PathFor(string appKey)
        => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TesterLoop",
            $"{appKey}-last-login.txt");
}
