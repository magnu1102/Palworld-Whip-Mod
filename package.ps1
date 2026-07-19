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
$oldZip = Join-Path $PSScriptRoot 'PalWhip.zip'
$stage = Join-Path $env:TEMP ("palwhip_package_{0}" -f [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force $stage | Out-Null
    foreach ($part in @(
        'PalWhip', 'PalBoombox', 'PalWhipItem', 'PalBoomboxItem',
        'install.ps1', 'README.md'
    )) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $part) -Destination $stage -Recurse -Force
    }

    # Runtime state is local to one machine/session and must never ship.
    $stagedIpc = Join-Path $stage 'PalBoombox\ipc'
    foreach ($runtimeFile in @(
        'state.txt', 'companion.txt', 'import_result.txt', 'menu_command.txt',
        'menu_show.txt', 'welcome_seen.txt', 'whip_key.txt', 'volume.txt'
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
} finally {
    if ($payloadZip -and (Test-Path -LiteralPath $payloadZip)) {
        Remove-Item -LiteralPath $payloadZip -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
