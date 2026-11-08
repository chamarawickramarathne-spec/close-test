using System.Text.Json.Serialization;

namespace TesterLoop.Desktop.Core;

public sealed record UpdateManifest(
    [property: JsonPropertyName("version")] string? Version,
    [property: JsonPropertyName("desktop_x86")] string? DesktopX86,
    [property: JsonPropertyName("desktop_x64")] string? DesktopX64,
    [property: JsonPropertyName("admin_x86")] string? AdminX86,
    [property: JsonPropertyName("admin_x64")] string? AdminX64,
    [property: JsonPropertyName("sha256_desktop_x86")] string? Sha256DesktopX86,
    [property: JsonPropertyName("sha256_desktop_x64")] string? Sha256DesktopX64,
    [property: JsonPropertyName("sha256_admin_x86")] string? Sha256AdminX86,
    [property: JsonPropertyName("sha256_admin_x64")] string? Sha256AdminX64);
