# Windows OpenSSL setup helper for VaultTheSpire
# Run this from PowerShell as Administrator.

$paths = @(
    'C:\Program Files\OpenSSL-Win64',
    'C:\Program Files\OpenSSL-Win32',
    'C:\OpenSSL-Win64',
    'C:\OpenSSL-Win32'
)

$installPath = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $installPath) {
    Write-Host 'OpenSSL not found in standard locations.' -ForegroundColor Yellow
    Write-Host 'Please install OpenSSL from https://slproweb.com/products/Win32OpenSSL.html and rerun this script.'
    exit 1
}

Write-Host "OpenSSL detected at $installPath" -ForegroundColor Green

$includePath = Join-Path $installPath 'include'
$libPath = Join-Path $installPath 'lib'
$cryptoLib = Join-Path $libPath 'libcrypto.lib'

if (-not (Test-Path $includePath)) {
    Write-Host "Include path not found: $includePath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $cryptoLib)) {
    Write-Host "Crypto libs not found at $cryptoLib" -ForegroundColor Red
    exit 1
}

Write-Host 'Setting environment variables...' -ForegroundColor Yellow
setx OPENSSL_ROOT_DIR "$installPath"
setx OPENSSL_INCLUDE_DIR "$includePath"
setx OPENSSL_CRYPTO_LIBRARY "$cryptoLib"

Write-Host 'OpenSSL environment variables set.' -ForegroundColor Green
Write-Host 'Please restart terminal/VS Code and rerun: flutter clean; flutter pub get; flutter run -d windows' -ForegroundColor Cyan
