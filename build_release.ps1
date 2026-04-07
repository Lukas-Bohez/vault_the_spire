# vault_the_spire — Release Build Script
# Run from the project root: .\build_release.ps1
# Outputs: build\releases\  (APK zip, AAB, Windows zip)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$releaseDir = Join-Path $projectRoot "build\releases"

Write-Host "=== vault_the_spire release builder ===" -ForegroundColor Cyan
Write-Host "Project: $projectRoot"
Write-Host "Output:  $releaseDir"
Write-Host ""

# ── Ensure output folder exists ─────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

# ── Read version from pubspec ────────────────────────────────────────────────
$pubspec = Get-Content "$projectRoot\pubspec.yaml" | Where-Object { $_ -match "^version:" }
$version = ($pubspec -split ":")[1].Trim().Split("+")[0]
Write-Host "Version: $version" -ForegroundColor Yellow
Write-Host ""

Set-Location $projectRoot

# ── 1. Flutter pub get ───────────────────────────────────────────────────────
Write-Host "[1/4] flutter pub get..." -ForegroundColor Green
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

# ── 2. Android APK (release, split per ABI for smaller size) ────────────────
Write-Host "[2/4] Building Android APK..." -ForegroundColor Green
flutter build apk --release --split-per-abi
if ($LASTEXITCODE -ne 0) { throw "APK build failed" }

$apkDir  = "$projectRoot\build\app\outputs\flutter-apk"
$apkZip  = "$releaseDir\vault_the_spire_${version}_android_apk.zip"

# Collect all release APKs (arm64, armeabi, x86_64)
$apks = Get-ChildItem $apkDir -Filter "app-*-release.apk"
if ($apks.Count -eq 0) {
    # Fallback: universal APK
    $apks = Get-ChildItem "$projectRoot\build\app\outputs\apk\release" -Filter "*.apk"
}

Write-Host "  Packaging $($apks.Count) APK(s) -> $apkZip"
Compress-Archive -Path $apks.FullName -DestinationPath $apkZip -Force
Write-Host "  APK zip: $apkZip" -ForegroundColor Green

# ── 3. Android AAB (App Bundle for Play Store) ──────────────────────────────
Write-Host "[3/4] Building Android AAB..." -ForegroundColor Green
flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { throw "AAB build failed" }

$aabSrc  = "$projectRoot\build\app\outputs\bundle\release\app-release.aab"
$aabDest = "$releaseDir\vault_the_spire_${version}_android.aab"
Copy-Item $aabSrc $aabDest -Force
Write-Host "  AAB: $aabDest" -ForegroundColor Green

# ── 4. Windows (x64 release) ────────────────────────────────────────────────
Write-Host "[4/4] Building Windows x64..." -ForegroundColor Green
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Windows build failed" }

$winSrc  = "$projectRoot\build\windows\x64\runner\Release"
$winZip  = "$releaseDir\vault_the_spire_${version}_windows_x64.zip"
Write-Host "  Packaging Windows build -> $winZip"
Compress-Archive -Path "$winSrc\*" -DestinationPath $winZip -Force
Write-Host "  Windows zip: $winZip" -ForegroundColor Green

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Build complete ===" -ForegroundColor Cyan
Write-Host "Output folder: $releaseDir"
Write-Host ""
Get-ChildItem $releaseDir | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 1)
    Write-Host ("  {0,-55} {1,6} MB" -f $_.Name, $size)
}
Write-Host ""
Write-Host ("Drag the files from " + $releaseDir + " into your 1 Upload folder.") -ForegroundColor Yellow