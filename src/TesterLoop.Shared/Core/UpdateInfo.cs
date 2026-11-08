namespace TesterLoop.Desktop.Core;

public sealed record UpdateInfo(
    string Version,
    string AssetName,
    string DownloadUrl,
    string Sha256);
