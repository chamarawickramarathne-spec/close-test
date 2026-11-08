using System.IO;
using System.Net;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace TesterLoop.Desktop.Core;

public sealed partial class UpdateService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly UpdateProduct _product;
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromMinutes(5) };

    public UpdateService(UpdateProduct product)
    {
        _product = product;
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("TesterLoop-Update/1.0");
    }

    public string ArchitectureLabel => IsX86 ? "x86" : "x64";

    public async Task<UpdateInfo?> CheckAsync(CancellationToken cancellationToken = default)
    {
        using var response = await SendWithRetryAsync(AppConfig.UpdateManifestUrl, cancellationToken);

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            throw new InvalidOperationException(
                "No update manifest is published for the latest release yet.");
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(
                $"The update server answered {(int)response.StatusCode}. Try again in a minute.");
        }

        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        UpdateManifest manifest;
        try
        {
            manifest = JsonSerializer.Deserialize<UpdateManifest>(body, JsonOptions)
                       ?? throw new InvalidOperationException("The update manifest was empty.");
        }
        catch (JsonException ex)
        {
            throw new InvalidOperationException("The update manifest could not be read.", ex);
        }

        if (!TryParseVersion(manifest.Version, out var latest))
        {
            throw new InvalidOperationException("The update manifest has no valid version.");
        }

        if (!TryParseVersion(AppConfig.AppVersion, out var current))
        {
            throw new InvalidOperationException("The installed version could not be read.");
        }

        if (latest <= current)
        {
            return null;
        }

        var (asset, hash) = _product == UpdateProduct.Admin
            ? (IsX86 ? manifest.AdminX86 : manifest.AdminX64,
               IsX86 ? manifest.Sha256AdminX86 : manifest.Sha256AdminX64)
            : (IsX86 ? manifest.DesktopX86 : manifest.DesktopX64,
               IsX86 ? manifest.Sha256DesktopX86 : manifest.Sha256DesktopX64);

        if (!IsAllowedAsset(asset))
        {
            throw new InvalidOperationException(
                "The update manifest points at an unexpected installer.");
        }

        if (!IsSha256(hash))
        {
            throw new InvalidOperationException(
                "The update manifest has no valid installer checksum.");
        }

        return new UpdateInfo(
            latest.ToString(),
            asset!,
            AppConfig.UpdateDownloadBase + asset,
            hash!);
    }

    public async Task<string> DownloadAsync(
        UpdateInfo update,
        IProgress<double>? progress,
        CancellationToken cancellationToken = default)
    {
        var folder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "TesterLoop",
            "updates");
        Directory.CreateDirectory(folder);

        var target = Path.Combine(folder, update.AssetName);
        var partial = target + ".partial";

        await DownloadWithRetryAsync(update.DownloadUrl, partial, progress, cancellationToken);

        var actual = await ComputeSha256Async(partial, cancellationToken);
        if (!string.Equals(actual, update.Sha256, StringComparison.OrdinalIgnoreCase))
        {
            File.Delete(partial);
            throw new InvalidOperationException(
                "The downloaded installer did not match its checksum. Try again.");
        }

        if (File.Exists(target))
        {
            File.Delete(target);
        }

        File.Move(partial, target);
        return target;
    }

    private async Task<HttpResponseMessage> SendWithRetryAsync(
        string url,
        CancellationToken cancellationToken)
    {
        Exception? last = null;

        for (var attempt = 1; attempt <= 3; attempt++)
        {
            try
            {
                var response = await _http.GetAsync(url, cancellationToken);
                if ((int)response.StatusCode < 500 || attempt == 3)
                {
                    return response;
                }

                response.Dispose();
                last = new HttpRequestException(
                    $"The update server answered {(int)response.StatusCode}.");
            }
            catch (Exception ex) when (
                !cancellationToken.IsCancellationRequested
                && ex is HttpRequestException or TaskCanceledException)
            {
                last = ex;
            }

            await Task.Delay(TimeSpan.FromSeconds(attempt), cancellationToken);
        }

        throw new InvalidOperationException(
            "The update server could not be reached. Check the network connection and try again.",
            last);
    }

    private async Task DownloadWithRetryAsync(
        string url,
        string path,
        IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        Exception? last = null;

        for (var attempt = 1; attempt <= 3; attempt++)
        {
            try
            {
                await DownloadOnceAsync(url, path, progress, cancellationToken);
                return;
            }
            catch (Exception ex) when (
                !cancellationToken.IsCancellationRequested
                && ex is HttpRequestException or IOException or TaskCanceledException)
            {
                last = ex;
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
            }

            await Task.Delay(TimeSpan.FromSeconds(attempt), cancellationToken);
        }

        throw new InvalidOperationException(
            "The update download failed. Check the network connection and try again.",
            last);
    }

    private async Task DownloadOnceAsync(
        string url,
        string path,
        IProgress<double>? progress,
        CancellationToken cancellationToken)
    {
        using var response = await _http.GetAsync(
            url,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            throw new InvalidOperationException(
                "The latest release does not include that installer. Use the releases page.");
        }

        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException(
                $"The update server answered {(int)response.StatusCode}.",
                null,
                response.StatusCode);
        }

        var length = response.Content.Headers.ContentLength;

        await using var input = await response.Content.ReadAsStreamAsync(cancellationToken);
        await using var output = new FileStream(
            path,
            FileMode.Create,
            FileAccess.Write,
            FileShare.None,
            81920,
            useAsync: true);

        var buffer = new byte[81920];
        long total = 0;
        int read;

        while ((read = await input.ReadAsync(buffer, cancellationToken)) > 0)
        {
            await output.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
            total += read;

            if (length is > 0)
            {
                progress?.Report((double)total / length.Value);
            }
        }

        if (length is > 0 && total != length.Value)
        {
            throw new IOException("The download ended before the whole installer arrived.");
        }

        progress?.Report(1);
    }

    private static async Task<string> ComputeSha256Async(
        string path,
        CancellationToken cancellationToken)
    {
        await using var stream = File.OpenRead(path);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(hash);
    }

    private static bool TryParseVersion(string? value, out Version version)
    {
        version = new Version(0, 0, 0);

        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var text = value.Trim();
        if (text.StartsWith('v') || text.StartsWith('V'))
        {
            text = text[1..];
        }

        if (Version.TryParse(text, out var parsed))
        {
            version = parsed;
            return true;
        }

        return false;
    }

    private bool IsAllowedAsset(string? asset)
    {
        if (string.IsNullOrWhiteSpace(asset) || !SafeAssetName().IsMatch(asset))
        {
            return false;
        }

        return _product == UpdateProduct.Admin
            ? asset.StartsWith("TesterLoop-Admin-Setup-", StringComparison.Ordinal)
            : asset.StartsWith("TesterLoop-Setup-", StringComparison.Ordinal);
    }

    private static bool IsSha256(string? hash)
        => hash is { Length: 64 } && hash.All(Uri.IsHexDigit);

    private static bool IsX86
        => RuntimeInformation.ProcessArchitecture == Architecture.X86;

    [GeneratedRegex("^[A-Za-z0-9._-]+\\.exe$")]
    private static partial Regex SafeAssetName();
}
