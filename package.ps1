# Packages the PalWhip mod into a zip ready for sharing / Nexus upload.
# The zip contains the PalWhip folder so it extracts straight into a UE4SS Mods directory.
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'PalWhip.zip'
if (Test-Path $out) { Remove-Item $out -Force }
Compress-Archive -Path (Join-Path $PSScriptRoot 'PalWhip') -DestinationPath $out
Write-Host "Created $out"
