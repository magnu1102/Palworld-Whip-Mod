# Packages the PalWhip + PalBoombox mods and one-click installer into a zip
# ready for sharing / Nexus upload.
# The zip contains:
#   PalWhip/        -> extract into  Pal\Binaries\Win64\ue4ss\Mods\
#   PalBoombox/     -> extract into  Pal\Binaries\Win64\ue4ss\Mods\
#   PalWhipItem/    -> extract into  Pal\Binaries\Win64\ue4ss\Mods\PalSchema\mods\
#   PalBoomboxItem/ -> extract into  Pal\Binaries\Win64\ue4ss\Mods\PalSchema\mods\
$ErrorActionPreference = 'Stop'

$music = Join-Path $PSScriptRoot 'PalBoombox\music'
# Never publish personal imports accidentally. Only the explicitly selected
# release recordings, with their reviewed hashes, may enter the package.
$bundledTracks = [ordered]@{
    'Sail the Raging Sea (Sea Shanty) - Windrose.mp3' = '7E17FAEBECF090EEC7AA5724FDB5CB07F34A06087B33DA17FBF36180D00C6315'
    'Bully in the Alley - New Early Access Version  Windrose Sea Shanty & Lyrics.mp3' = '9135E30CA26329F8E7FBF3C3C4607956C2F0934A22479602D4A40D52BED7F469'
    'Leave Her Johnny - New Early Access Version  Windrose Sea Shanty & Lyrics.mp3' = '9E32040F696FD21C78DAFBE915238CDB0916FCAF40B1B0EDEE9E42DB107B8B90'
}
$unexpectedTracks = Get-ChildItem -LiteralPath $music -Recurse -File |
    Where-Object {
        $_.DirectoryName -ne $music -or -not $bundledTracks.Contains($_.Name)
    }
if ($unexpectedTracks) {
    $names = ($unexpectedTracks.Name | Sort-Object) -join ', '
    throw "Refusing to package non-release music files: $names. Keep personal tracks only in the installed PalBoombox\music folder."
}
foreach ($track in $bundledTracks.Keys) {
    $trackPath = Join-Path $music $track
    if (-not (Test-Path -LiteralPath $trackPath)) {
        throw "Bundled track is missing: $track"
    }
    $actualHash = (Get-FileHash -LiteralPath $trackPath -Algorithm SHA256).Hash
    if ($actualHash -ne $bundledTracks[$track]) {
        throw "Bundled track hash does not match the reviewed recording: $track"
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
