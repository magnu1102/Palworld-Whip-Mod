# Packages the PalWhip + PalBoombox mods into a zip ready for sharing / Nexus upload.
# The zip contains:
#   PalWhip/        -> extract into  Pal\Binaries\Win64\ue4ss\Mods\
#   PalBoombox/     -> extract into  Pal\Binaries\Win64\ue4ss\Mods\
#   PalWhipItem/    -> extract into  Pal\Binaries\Win64\ue4ss\Mods\PalSchema\mods\
#   PalBoomboxItem/ -> extract into  Pal\Binaries\Win64\ue4ss\Mods\PalSchema\mods\
$ErrorActionPreference = 'Stop'

# Generate the shanty WAVs if they're missing (they're gitignored).
$music = Join-Path $PSScriptRoot 'PalBoombox\music'
if (-not (Test-Path (Join-Path $music 'wellerman.wav'))) {
    Write-Host 'Generating shanty audio...'
    python (Join-Path $PSScriptRoot 'tools\make_shanties.py')
}

$out = Join-Path $PSScriptRoot 'PalWhip.zip'
if (Test-Path $out) { Remove-Item $out -Force }
$parts = @('PalWhip', 'PalBoombox', 'PalWhipItem', 'PalBoomboxItem', 'README.md') |
    ForEach-Object { Join-Path $PSScriptRoot $_ }
Compress-Archive -Path $parts -DestinationPath $out
Write-Host "Created $out"
