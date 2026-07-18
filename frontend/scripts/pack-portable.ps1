<#
.SYNOPSIS
    Build Meetily as a portable Windows zip package.

.DESCRIPTION
    Builds the Tauri app in release mode and assembles a self-contained
    portable folder + zip archive. When `portable.txt` sits next to the
    executable, the app stores its database, models, recordings, templates,
    and notification settings under `./data/` instead of `%APPDATA%`.

.PARAMETER SkipBuild
    Reuse an existing `target/release/meetily.exe` and only re-pack.

.PARAMETER OutputDir
    Where the produced folder and zip land. Defaults to `<repo>/dist`.

.EXAMPLE
    pnpm run pack:portable
    powershell -File scripts/pack-portable.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

# --- Locate repo layout ---------------------------------------------------
$FrontendDir = Split-Path -Parent $PSScriptRoot          # <repo>/frontend
$RepoRoot    = Split-Path -Parent $FrontendDir           # <repo>
$SrcTauri    = Join-Path $FrontendDir "src-tauri"
$Conf        = Join-Path $SrcTauri "tauri.conf.json"

if (-not $OutputDir) { $OutputDir = Join-Path $RepoRoot "dist" }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# --- Read version + product name -----------------------------------------
$confJson    = Get-Content -Raw $Conf | ConvertFrom-Json
$version     = $confJson.version
$productName = $confJson.productName
if (-not $productName) { $productName = "meetily" }
Write-Host "[pack] $productName $version"

# --- Build (unless skipped) ----------------------------------------------
if (-not $SkipBuild) {
    Push-Location $FrontendDir
    try {
        Write-Host "[pack] running: pnpm run tauri:build --bundles none"
        & pnpm run tauri:build -- --bundles none
        if ($LASTEXITCODE -ne 0) { throw "tauri build failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

# --- Locate the built exe -------------------------------------------------
$exeCandidates = @(
    (Join-Path $SrcTauri "target/release/$productName.exe"),
    (Join-Path $SrcTauri "target/release/meetily.exe")
)
$exePath = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exePath) {
    throw "Could not find built exe. Looked at: $($exeCandidates -join ', ')"
}
Write-Host "[pack] exe: $exePath"

# --- Stage portable folder -----------------------------------------------
$stageName = "$productName-portable-$version-windows-x64"
$stageDir  = Join-Path $OutputDir $stageName
if (Test-Path $stageDir) { Remove-Item -Recurse -Force $stageDir }
New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

# 1) main executable
Copy-Item $exePath (Join-Path $stageDir (Split-Path -Leaf $exePath))

# 2) portable marker + empty data dir
"Meetily portable mode marker. Delete this file to fall back to %APPDATA%." |
    Set-Content -Encoding utf8NoBOM -Path (Join-Path $stageDir "portable.txt")
New-Item -ItemType Directory -Force -Path (Join-Path $stageDir "data") | Out-Null

# 3) bundled resources (templates)
$templatesSrc = Join-Path $SrcTauri "templates"
if (Test-Path $templatesSrc) {
    $resDir = Join-Path $stageDir "resources/templates"
    New-Item -ItemType Directory -Force -Path $resDir | Out-Null
    Copy-Item (Join-Path $templatesSrc "*.json") $resDir
    Write-Host "[pack] copied templates -> resources/templates/"
} else {
    Write-Warning "[pack] templates/ not found at $templatesSrc"
}

# 4) external binaries (llama-helper, ffmpeg) if present
$binariesSrc = Join-Path $SrcTauri "binaries"
if (Test-Path $binariesSrc) {
    $binDst = Join-Path $stageDir "binaries"
    New-Item -ItemType Directory -Force -Path $binDst | Out-Null
    Copy-Item (Join-Path $binariesSrc "*") $binDst -Recurse
    Write-Host "[pack] copied external binaries -> binaries/"
} else {
    Write-Host "[pack] no binaries/ found (optional)"
}

# 5) short README next to the exe
@"
Meetily portable ($version)

Just double-click ``$productName.exe``. All data is written under ``.\data\``:

    .\data\meeting_minutes.sqlite   - meetings database
    .\data\models\                  - Whisper / Parakeet / summary models
    .\data\recordings\              - captured audio
    .\data\templates\               - user-added summary templates
    .\data\notifications.json       - notification preferences

Delete ``portable.txt`` to make the app fall back to ``%APPDATA%\com.meetily.ai``.

To move to another machine or USB stick, simply copy this whole folder.
"@ | Set-Content -Encoding utf8NoBOM -Path (Join-Path $stageDir "README.txt")

# --- Zip it up ------------------------------------------------------------
$zipPath = Join-Path $OutputDir "$stageName.zip"
if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
Write-Host "[pack] compressing -> $zipPath"
Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

$sizeMb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host ""
Write-Host "[pack] done."
Write-Host "  folder : $stageDir"
Write-Host "  zip    : $zipPath  ($sizeMb MB)"
