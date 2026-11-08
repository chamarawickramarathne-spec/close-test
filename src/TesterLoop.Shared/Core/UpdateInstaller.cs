using System.ComponentModel;
using System.IO;
using System.Diagnostics;

namespace TesterLoop.Desktop.Core;

public static class UpdateInstaller
{
    public static bool TryStart(string path)
    {
        try
        {
            Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
            return true;
        }
        catch (Exception ex) when (ex is Win32Exception or InvalidOperationException or FileNotFoundException)
        {
            return false;
        }
    }
}
