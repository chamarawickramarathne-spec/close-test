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
