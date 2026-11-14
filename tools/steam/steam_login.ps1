# One-time Steam login for the automatic Steam uploads (the steam job in .github/workflows/release.yml).
# Run on Patrick's Windows PC in PowerShell:
#   powershell -ExecutionPolicy Bypass -File tools\steam\steam_login.ps1
# or straight from GitHub without a checkout:
#   irm https://raw.githubusercontent.com/patrickcerny/better-at-gambling/main/tools/steam/steam_login.ps1 | iex
#
# It downloads Valve's steamcmd, logs in once (you type your Steam password and the Steam Guard
# code in this window; nothing is stored by this script), then copies steamcmd's saved login
# (config\config.vdf, base64) to the clipboard and opens the GitHub page for the secret.
# Paste it as STEAM_CONFIG_VDF and add STEAM_USERNAME with your Steam login name. That's all:
# every later release is uploaded to Steam by GitHub Actions (it is not set live on its own).
# If Steam ever asks for Steam Guard again (the saved login expired), run this again.
$ErrorActionPreference = "Stop"
$dir = Join-Path $env:LOCALAPPDATA "BetterAtGambling-steamcmd"
$exe = Join-Path $dir "steamcmd.exe"
if (-not (Test-Path $exe)) {
	New-Item -ItemType Directory -Force -Path $dir | Out-Null
	$zip = Join-Path $dir "steamcmd.zip"
	Write-Host "Downloading steamcmd from Valve ..."
	Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $zip
	Expand-Archive -Path $zip -DestinationPath $dir -Force
	Remove-Item $zip
}
$user = Read-Host "Steam login name (the account that owns the Steamworks app)"
Write-Host "steamcmd now asks for your password and the Steam Guard code ..."
& $exe +login $user +quit
$vdf = Join-Path $dir "config\config.vdf"
if (-not (Test-Path $vdf)) { throw "Login did not finish (no $vdf). Run the script again." }
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($vdf))
Set-Clipboard -Value $b64
Write-Host ""
Write-Host "Done. The saved login is in your clipboard."
Write-Host "On the GitHub page that opens now:"
Write-Host "  1. Name: STEAM_CONFIG_VDF   Secret: paste (Ctrl+V)   -> Add secret"
Write-Host "  2. New secret again: Name: STEAM_USERNAME   Secret: $user   -> Add secret"
Start-Process "https://github.com/patrickcerny/better-at-gambling/settings/secrets/actions/new"
