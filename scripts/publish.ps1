param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$dotnet = Join-Path $root ".tools\dotnet-sdk\dotnet.exe"
if (-not (Test-Path $dotnet)) {
    $dotnet = "dotnet"
}

$apps = @(
    @{
        Project = Join-Path $root "src\TesterLoop.Desktop\TesterLoop.Desktop.csproj"
        Exe = "TesterLoop.exe"
        Output = "win-{0}"
    },
    @{
        Project = Join-Path $root "src\TesterLoop.Admin\TesterLoop.Admin.csproj"
        Exe = "TesterLoopAdmin.exe"
        Output = "admin-win-{0}"
    }
)

foreach ($arch in @("x86", "x64")) {
    $rid = "win-$arch"
    foreach ($app in $apps) {
        $folder = $app.Output -f $arch
        $out = Join-Path $root "build\$folder"
        Write-Host "Publishing $folder -> $out"

        & $dotnet publish $app.Project `
            -c $Configuration `
            -r $rid `
            --self-contained true `
            -p:PublishTrimmed=false `
            -p:DebugType=none `
            -o $out

        if ($LASTEXITCODE -ne 0) {
            throw "dotnet publish failed for $folder with exit code $LASTEXITCODE"
        }

        $exe = Join-Path $out $app.Exe
        if (-not (Test-Path $exe)) {
            throw "Publish for $folder did not produce $($app.Exe)"
        }
    }
}

Write-Host "Done. Main output under build\win-*, admin output under build\admin-win-*."
