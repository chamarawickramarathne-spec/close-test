param(
    [string]$IsccPath = ""
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot

if (-not $IsccPath) {
    $candidates = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        "E:\AIprojects\AI Agent\InnoSetup\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    $IsccPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $IsccPath) {
    throw "Inno Setup 6 not found. Install it, or pass -IsccPath."
}

$builds = @(
    @{
        Iss = Join-Path $root "installer\TesterLoop.iss"
        Source = "build\win-{0}\TesterLoop.exe"
        Output = "build\win-{0}"
    },
    @{
        Iss = Join-Path $root "installer\TesterLoop.Admin.iss"
        Source = "build\admin-win-{0}\TesterLoopAdmin.exe"
        Output = "build\admin-win-{0}"
    }
)

foreach ($arch in @("x86", "x64")) {
    foreach ($build in $builds) {
        $source = Join-Path $root ($build.Source -f $arch)
        if (-not (Test-Path $source)) {
            throw "Missing $source. Run scripts\publish.ps1 first."
        }

        & $IsccPath "/DArch=$arch" $build.Iss
        if ($LASTEXITCODE -ne 0) {
            throw "ISCC failed for $($build.Iss) $arch with exit code $LASTEXITCODE"
        }

        Write-Host "Installer written to $($build.Output -f $arch)"
    }
}

$appConfigPath = Join-Path $root "src\TesterLoop.Shared\Core\AppConfig.cs"
$appConfig = [System.IO.File]::ReadAllText($appConfigPath)
if ($appConfig -notmatch 'AppVersion\s*=\s*"([0-9.]+)"') {
    throw "Could not read AppVersion from $appConfigPath"
}
$version = $Matches[1]

function Get-InstallerHash {
    param([string]$RelativePath)

    $path = Join-Path $root $RelativePath
    if (-not (Test-Path $path)) {
        throw "Missing installer for update manifest: $path"
    }

    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$manifest = [ordered]@{
    version           = $version
    desktop_x86       = "TesterLoop-Setup-x86.exe"
    desktop_x64       = "TesterLoop-Setup-x64.exe"
    admin_x86         = "TesterLoop-Admin-Setup-x86.exe"
    admin_x64         = "TesterLoop-Admin-Setup-x64.exe"
    sha256_desktop_x86 = Get-InstallerHash "build\win-x86\TesterLoop-Setup-x86.exe"
    sha256_desktop_x64 = Get-InstallerHash "build\win-x64\TesterLoop-Setup-x64.exe"
    sha256_admin_x86   = Get-InstallerHash "build\admin-win-x86\TesterLoop-Admin-Setup-x86.exe"
    sha256_admin_x64   = Get-InstallerHash "build\admin-win-x64\TesterLoop-Admin-Setup-x64.exe"
}

$manifestPath = Join-Path $root "build\desktop-version.json"
$manifestJson = ($manifest | ConvertTo-Json) + "`r`n"
[System.IO.File]::WriteAllText(
    $manifestPath,
    $manifestJson,
    (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Update manifest written to $manifestPath (version $version)."

