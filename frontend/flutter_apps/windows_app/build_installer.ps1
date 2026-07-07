# Build MyTaskKing Windows single-file installer (mytaskking_windows_setup_1.0.0.exe)
# Requires: Flutter SDK, Inno Setup 6 (ISCC.exe)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$ApiUrl = "https://mytaskking.com"
$SocketUrl = "https://mytaskking.com"

Write-Host "==> Flutter release build (API: $ApiUrl)" -ForegroundColor Cyan
flutter build windows --release `
  --dart-define=API_URL=$ApiUrl `
  --dart-define=SOCKET_URL=$SocketUrl
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$releaseDir = Join-Path $PSScriptRoot "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $releaseDir "mytaskking_windows.exe"))) {
  Write-Error "Release binary not found at $releaseDir\mytaskking_windows.exe"
}

$isccCandidates = @(
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
  Write-Error "Inno Setup 6 not found. Install from https://jrsoftware.org/isinfo.php"
}

Write-Host "==> Compiling installer with Inno Setup" -ForegroundColor Cyan
& $iscc (Join-Path $PSScriptRoot "installer\mytaskking_windows.iss")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$setup = Join-Path $PSScriptRoot "build\installer\mytaskking_windows_setup_1.0.0.exe"
if (-not (Test-Path $setup)) {
  Write-Error "Installer was not created at $setup"
}

$sizeMb = [math]::Round((Get-Item $setup).Length / 1MB, 1)
Write-Host ""
Write-Host "Done. Single-file installer:" -ForegroundColor Green
Write-Host "  $setup" -ForegroundColor White
Write-Host "  Size: ${sizeMb} MB" -ForegroundColor Gray
Write-Host ""
Write-Host "Share only this .exe - it bundles the full app." -ForegroundColor Gray
