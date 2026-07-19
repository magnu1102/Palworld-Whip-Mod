# Builds a single self-extracting PalWhip installer executable. The executable
# embeds a private zip payload containing:
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
    'Bully In The Alley (Sea Shanty) - Windrose.mp3' = 'ED830BE1B5C1C870BD1314479A7E959B4C8B3D2616559717666A17EE77FD5C12'
    'Leave Her Johnny (Sea Shanty) - Windrose.mp3' = '7B0F6B590DD10C26B5EB2AC8F5F90B1B2E675EF0E3457AAE57F049E2FD702F76'
    'Maggie May (Sea Shanty) - Windrose.mp3' = 'FE92F861A7AD7D06AA788CFFCDBB225B47E07FF03DAB6D893C563F91B6BEEFEB'
    'Blow The Man Down (Sea Shanty) - Windrose.mp3' = 'D36AC94DFD2B13EDBA837261F756A8A8B878BD61936DD8C38588865246D70569'
    'Drunken Sailor (Sea Shanty) - Windrose.mp3' = 'A312EF92290EC100F8EA116238711E2BE530D249306FE52D685C71677F5D24DA'
    '12 Years a Slave 2013   Roll Jordan Roll.mp3' = '118021523C44364D6E2E46D1F25B74EBEAE152D1769F68FCC5F7005C583308F3'
    'Down to the River to Pray.mp3' = '358B7CE8A69987BBA7FCC5A41AE8EC3E5AFC87CD61981EFC21D36B378D5A1A81'
    'gonna see miss liza....mp3' = 'E722C6E70949C35D24FB7806FB03E1C0929C72E61A4C06509B3FA0FA8B1B7426'
}
$manifestPath = Join-Path $PSScriptRoot 'PalBoombox\bundled_tracks.txt'
$manifestTracks = @(
    Get-Content -LiteralPath $manifestPath -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
if ($manifestTracks.Count -ne $bundledTracks.Count -or
    @($manifestTracks | Where-Object { -not $bundledTracks.Contains($_) }).Count -ne 0) {
    throw 'bundled_tracks.txt does not exactly match the reviewed release recordings.'
}
$expectedPlaylistRows = @(
    '108.147|Blow The Man Down (Sea Shanty) - Windrose.mp3'
    '147.409|Bully In The Alley (Sea Shanty) - Windrose.mp3'
    '80.248|Drunken Sailor (Sea Shanty) - Windrose.mp3'
    '126.407|Leave Her Johnny (Sea Shanty) - Windrose.mp3'
    '163.187|Maggie May (Sea Shanty) - Windrose.mp3'
    '87.928|Sail the Raging Sea (Sea Shanty) - Windrose.mp3'
    '118.152|12 Years a Slave 2013   Roll Jordan Roll.mp3'
    '177.215|Down to the River to Pray.mp3'
    '56.111|gonna see miss liza....mp3'
)
$actualPlaylistRows = @(
    Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PalBoombox\shared_playlist.txt') -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') }
)
if (($actualPlaylistRows -join "`n") -cne ($expectedPlaylistRows -join "`n")) {
    throw 'shared_playlist.txt does not exactly match the reviewed release track timing.'
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

$out = Join-Path $PSScriptRoot 'PalWhip-Setup.exe'
$manualOut = Join-Path $PSScriptRoot 'PalWhip-Manual.zip'
$uninstallerOut = Join-Path $PSScriptRoot 'PalWhip-Uninstaller.zip'
$oldZip = Join-Path $PSScriptRoot 'PalWhip.zip'
$stage = Join-Path $env:TEMP ("palwhip_package_{0}" -f [Guid]::NewGuid().ToString('N'))
$manualStage = Join-Path $env:TEMP ("palwhip_manual_{0}" -f [Guid]::NewGuid().ToString('N'))
$uninstallerStage = Join-Path $env:TEMP ("palwhip_uninstaller_{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force $stage | Out-Null
    foreach ($part in @(
        'PalWhip', 'PalBoombox', 'PalWhipItem', 'PalBoomboxItem',
        'install.ps1', 'Uninstall-PalWhip.ps1', 'Uninstall-PalWhip.cmd', 'README.md'
    )) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $part) -Destination $stage -Recurse -Force
    }

    # Retain the historical source asset for development history, but do not
    # ship or register it. boombox-v2.png is the only referenced release icon.
    $stagedLegacyIcon = Join-Path $stage 'PalBoomboxItem\resources\images\boombox.png'
    if (Test-Path -LiteralPath $stagedLegacyIcon) {
        Remove-Item -LiteralPath $stagedLegacyIcon -Force
    }

    # Runtime state is local to one machine/session and must never ship.
    $stagedIpc = Join-Path $stage 'PalBoombox\ipc'
    foreach ($runtimeFile in @(
        'state.txt', 'companion.txt', 'volume.txt'
    )) {
        $runtimePath = Join-Path $stagedIpc $runtimeFile
        if (Test-Path -LiteralPath $runtimePath) {
            Remove-Item -LiteralPath $runtimePath -Force
        }
    }

    $payloadZip = Join-Path $env:TEMP ("palwhip_payload_{0}.zip" -f [Guid]::NewGuid().ToString('N'))
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $payloadZip

    $compiler = @(
        'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
        'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $compiler) {
        throw 'The Windows .NET Framework C# compiler was not found.'
    }

    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
    $compilerArgs = @(
        '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu',
        ("/win32manifest:{0}" -f (Join-Path $PSScriptRoot 'installer\PalWhipSetup.manifest')),
        ("/resource:{0},PalWhip.Payload.zip" -f $payloadZip),
        '/reference:System.Windows.Forms.dll',
        '/reference:System.IO.Compression.dll',
        '/reference:System.IO.Compression.FileSystem.dll',
        ("/out:{0}" -f $out),
        (Join-Path $PSScriptRoot 'installer\PalWhipSetup.cs')
    )
    & $compiler $compilerArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        throw 'Could not compile PalWhip-Setup.exe.'
    }
    if (Test-Path -LiteralPath $oldZip) { Remove-Item -LiteralPath $oldZip -Force }
    Write-Host "Created $out"

    # Build a ready-to-extract archive for users whose security policy blocks
    # unsigned self-extracting executables. The two config files are omitted so
    # a manual update cannot overwrite personal settings; Lua has safe defaults
    # for a fresh install.
    $manualMods = Join-Path $manualStage 'Pal\Binaries\Win64\ue4ss\Mods'
    $manualSchemaMods = Join-Path $manualMods 'PalSchema\mods'
    New-Item -ItemType Directory -Force $manualMods, $manualSchemaMods | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PalWhip') -Destination $manualMods -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PalBoombox') -Destination $manualMods -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PalWhipItem') -Destination $manualSchemaMods -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'PalBoomboxItem') -Destination $manualSchemaMods -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MANUAL-INSTALL.txt') -Destination $manualStage -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall-PalWhip.ps1') -Destination $manualStage -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall-PalWhip.cmd') -Destination $manualStage -Force

    foreach ($manualOnlyFile in @(
        (Join-Path $manualMods 'PalWhip\Scripts\config.lua'),
        (Join-Path $manualMods 'PalBoombox\Scripts\config.lua'),
        (Join-Path $manualSchemaMods 'PalBoomboxItem\resources\images\boombox.png')
    )) {
        if (Test-Path -LiteralPath $manualOnlyFile) {
            Remove-Item -LiteralPath $manualOnlyFile -Force
        }
    }
    $manualIpc = Join-Path $manualMods 'PalBoombox\ipc'
    foreach ($runtimeFile in 'state.txt', 'companion.txt', 'volume.txt') {
        $runtimePath = Join-Path $manualIpc $runtimeFile
        if (Test-Path -LiteralPath $runtimePath) {
            Remove-Item -LiteralPath $runtimePath -Force
        }
    }

    if (Test-Path -LiteralPath $manualOut) { Remove-Item -LiteralPath $manualOut -Force }
    Compress-Archive -Path (Join-Path $manualStage '*') -DestinationPath $manualOut
    Write-Host "Created $manualOut"

    New-Item -ItemType Directory -Force $uninstallerStage | Out-Null
    foreach ($uninstallerFile in 'Uninstall-PalWhip.ps1', 'Uninstall-PalWhip.cmd', 'UNINSTALL-README.txt') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $uninstallerFile) -Destination $uninstallerStage -Force
    }
    if (Test-Path -LiteralPath $uninstallerOut) { Remove-Item -LiteralPath $uninstallerOut -Force }
    Compress-Archive -Path (Join-Path $uninstallerStage '*') -DestinationPath $uninstallerOut
    Write-Host "Created $uninstallerOut"
} finally {
    if ($payloadZip -and (Test-Path -LiteralPath $payloadZip)) {
        Remove-Item -LiteralPath $payloadZip -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $manualStage) {
        Remove-Item -LiteralPath $manualStage -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $uninstallerStage) {
        Remove-Item -LiteralPath $uninstallerStage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
