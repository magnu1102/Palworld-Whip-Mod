# Packages the PalWhip mod into a zip ready for sharing / Nexus upload.
# The zip contains:
#   PalWhip/     -> extract into  Pal\Binaries\Win64\ue4ss\Mods\
#   PalWhipItem/ -> extract into  Pal\Binaries\Win64\ue4ss\Mods\PalSchema\mods\
$ErrorActionPreference = 'Stop'
$out = Join-Path $PSScriptRoot 'PalWhip.zip'
if (Test-Path $out) { Remove-Item $out -Force }
Compress-Archive -Path (Join-Path $PSScriptRoot 'PalWhip'), (Join-Path $PSScriptRoot 'PalWhipItem'), (Join-Path $PSScriptRoot 'README.md') -DestinationPath $out
Write-Host "Created $out"
