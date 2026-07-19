# Packages the PalWhip + PalBoombox mods and one-click installer into a zip
# ready for sharing / Nexus upload.
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

# Never publish personal imports accidentally. Only the four generated,
# public-domain shanty arrangements belong in the release package.
$bundledTracks = @(
    'bully_in_the_alley.wav',
    'drunken_sailor.wav',
    'leave_her_johnny.wav',
    'wellerman.wav'
)
$unexpectedTracks = Get-ChildItem -LiteralPath $music -Recurse -File |
    Where-Object {
        $_.DirectoryName -ne $music -or $_.Name -notin $bundledTracks
    }
if ($unexpectedTracks) {
    $names = ($unexpectedTracks.Name | Sort-Object) -join ', '
    throw "Refusing to package personal music files: $names. Keep personal tracks only in the installed PalBoombox\music folder."
}
foreach ($track in $bundledTracks) {
    if (-not (Test-Path -LiteralPath (Join-Path $music $track))) {
        throw "Bundled track is missing: $track"
    }
}

$out = Join-Path $PSScriptRoot 'PalWhip.zip'
$stage = Join-Path $env:TEMP ("palwhip_package_{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force $stage | Out-Null
    foreach ($part in @(
        'PalWhip', 'PalBoombox', 'PalWhipItem', 'PalBoomboxItem',
        'Install PalWhip.bat', 'install.ps1', 'README.md'
    )) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $part) -Destination $stage -Recurse -Force
    }

    # Runtime state is local to one machine/session and must never ship.
    $stagedIpc = Join-Path $stage 'PalBoombox\ipc'
    foreach ($runtimeFile in @(
        'state.txt', 'companion.txt', 'import_result.txt', 'menu_command.txt',
        'menu_show.txt', 'welcome_seen.txt', 'whip_key.txt'
    )) {
        $runtimePath = Join-Path $stagedIpc $runtimeFile
        if (Test-Path -LiteralPath $runtimePath) {
            Remove-Item -LiteralPath $runtimePath -Force
        }
    }

    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $out
    Write-Host "Created $out"
} finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
