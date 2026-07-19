$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$tempRoot = Join-Path $env:TEMP ("palwhip_release_test_{0}" -f [Guid]::NewGuid().ToString('N'))
$utf8NoBom = New-Object Text.UTF8Encoding($false)

function Assert([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERTION FAILED: $message" }
}

function Read-KeyValueFile([string]$path) {
    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) { $values[$parts[0]] = $parts[1] }
    }
    return $values
}

try {
    Write-Host 'Checking PowerShell syntax...'
    Get-ChildItem -LiteralPath $repo -Recurse -Filter '*.ps1' |
        Where-Object { $_.FullName -notlike "$tempRoot*" } |
        ForEach-Object {
            $tokens = $null
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
            Assert ($errors.Count -eq 0) "PowerShell parse errors in $($_.FullName): $errors"
        }

    Write-Host 'Checking Lua syntax...'
    $npx = Get-Command npx -ErrorAction SilentlyContinue
    Assert ($null -ne $npx) 'npx is required for the Lua syntax regression check.'
    foreach ($luaFile in (Get-ChildItem -LiteralPath (Join-Path $repo 'PalWhip'), (Join-Path $repo 'PalBoombox') -Recurse -Filter '*.lua')) {
        & npx --yes luaparse $luaFile.FullName | Out-Null
        Assert ($LASTEXITCODE -eq 0) "Lua parse failed: $($luaFile.FullName)"
    }

    Write-Host 'Checking Pal Tools XAML...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $repo 'PalBoombox\companion\control_panel.ps1') -ValidateOnly | Out-Host
    Assert ($LASTEXITCODE -eq 0) 'Pal Tools XAML validation failed.'

    Write-Host 'Checking item JSON...'
    Get-ChildItem -LiteralPath (Join-Path $repo 'PalWhipItem'), (Join-Path $repo 'PalBoomboxItem') -Recurse -Filter '*.json' |
        ForEach-Object { [void](Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json) }

    Write-Host 'Checking crash-capable marker calls are absent...'
    $boomboxLua = [IO.File]::ReadAllText((Join-Path $repo 'PalBoombox\Scripts\main.lua'))
    foreach ($unsafeText in 'SpawnActorBroadcast', 'BeginDeferredActorSpawnFromClass', 'FinishSpawningActor', 'StaticMeshActor') {
        Assert (-not $boomboxLua.Contains($unsafeText)) "Unsafe marker code remains: $unsafeText"
    }

    Write-Host 'Checking persistent GUI volume controls...'
    $controlPanel = [IO.File]::ReadAllText((Join-Path $repo 'PalBoombox\companion\control_panel.ps1'))
    foreach ($volumeCommand in 'volume_down', 'volume_up') {
        Assert ($boomboxLua.Contains($volumeCommand)) "Lua is missing volume command: $volumeCommand"
        Assert ($controlPanel.Contains($volumeCommand)) "Pal Tools is missing volume command: $volumeCommand"
    }
    Assert ($boomboxLua.Contains('ipc/volume.txt')) 'Listening volume is not persisted between sessions.'
    Assert ($controlPanel.Contains('Content="-"')) 'Volume-down button is not using an encoding-safe ASCII label.'
    Assert ($controlPanel.Contains('VolumeValueText')) 'Pal Tools does not display the current listening volume.'
    Assert ($controlPanel.Contains('IsEnabled = $script:displayedVolume -lt 200')) 'Volume boost is not available up to 200%.'

    Write-Host 'Testing culture-invariant companion values...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $repo 'PalBoombox\companion\boombox_companion.ps1') -ValidateOnly
    Assert ($LASTEXITCODE -eq 0) 'Companion invariant-number self-test failed.'

    Write-Host 'Testing music importer content deduplication...'
    $fixture = Join-Path $tempRoot 'importer\PalBoombox'
    $fixtureCompanion = Join-Path $fixture 'companion'
    $fixtureSource = Join-Path $tempRoot 'source\same-song.mp3'
    New-Item -ItemType Directory -Force $fixtureCompanion, (Split-Path $fixtureSource -Parent) | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'PalBoombox\companion\import_music.ps1') -Destination $fixtureCompanion
    [IO.File]::WriteAllBytes($fixtureSource, [byte[]](1, 7, 3, 9, 2, 6, 5, 4))
    $importer = Join-Path $fixtureCompanion 'import_music.ps1'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $importer -RequestId first -SourceFiles $fixtureSource
    Assert ($LASTEXITCODE -eq 0) 'First import failed.'
    $first = Read-KeyValueFile (Join-Path $fixture 'ipc\import_result.txt')
    Assert ($first.status -eq 'imported' -and $first.count -eq '1') 'First import result was not imported/count=1.'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $importer -RequestId second -SourceFiles $fixtureSource
    Assert ($LASTEXITCODE -eq 0) 'Duplicate import failed.'
    $second = Read-KeyValueFile (Join-Path $fixture 'ipc\import_result.txt')
    Assert ($second.status -eq 'unchanged' -and $second.count -eq '0') 'Duplicate import was not skipped.'
    $importedFiles = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'music') -File)
    Assert ($importedFiles.Count -eq 1) 'Duplicate import created another music file.'

    Write-Host 'Testing an upgrade preserves config and every personal music file...'
    $mockGame = Join-Path $tempRoot 'mock-game'
    $mockWin64 = Join-Path $mockGame 'Pal\Binaries\Win64'
    $mockMods = Join-Path $mockWin64 'ue4ss\Mods'
    $mockBoombox = Join-Path $mockMods 'PalBoombox'
    $mockMusic = Join-Path $mockBoombox 'music'
    $mockConfig = Join-Path $mockBoombox 'Scripts\config.lua'
    New-Item -ItemType Directory -Force `
        (Join-Path $mockWin64 'ue4ss'), `
        (Join-Path $mockMods 'PalSchema\dlls'), `
        $mockMusic, `
        (Split-Path $mockConfig -Parent) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $mockWin64 'ue4ss\UE4SS.dll'), [byte[]](1))
    [IO.File]::WriteAllBytes((Join-Path $mockWin64 'dwmapi.dll'), [byte[]](1))
    [IO.File]::WriteAllBytes((Join-Path $mockMods 'PalSchema\dlls\main.dll'), [byte[]](1))
    [IO.File]::WriteAllText((Join-Path $mockWin64 'ue4ss\UE4SS-settings.ini'), "GraphicsAPI = dx11`nbUseUObjectArrayCache = false", $utf8NoBom)
    $customConfigText = "return { MasterVolume = 0.42 }"
    [IO.File]::WriteAllText($mockConfig, $customConfigText, $utf8NoBom)
    [IO.File]::WriteAllBytes((Join-Path $mockMusic 'Personal Track.mp3'), [byte[]](11, 22, 33, 44, 55))
    # Generate the previous release's deterministic WAVs into the disposable
    # test tree. An exact legacy file must be migrated away, while a custom
    # replacement that merely shares an old filename must remain untouched.
    $legacyFixture = Join-Path $tempRoot 'legacy-generated-music'
    $previousShantyOutput = $env:PALBOOMBOX_SHANTY_OUT_DIR
    try {
        $env:PALBOOMBOX_SHANTY_OUT_DIR = $legacyFixture
        & python (Join-Path $repo 'tools\make_shanties.py') | Out-Host
        Assert ($LASTEXITCODE -eq 0) 'Could not generate the legacy music migration fixture.'
    } finally {
        $env:PALBOOMBOX_SHANTY_OUT_DIR = $previousShantyOutput
    }
    Copy-Item -LiteralPath (Join-Path $legacyFixture 'wellerman.wav') -Destination $mockMusic
    [IO.File]::WriteAllBytes((Join-Path $mockMusic 'drunken_sailor.wav'), [byte[]](9, 8, 7, 6, 5))
    New-Item -ItemType Directory -Force (Join-Path $mockMusic 'playlists') | Out-Null
    [IO.File]::WriteAllText((Join-Path $mockMusic 'playlists\keep-me.txt'), 'personal metadata', $utf8NoBom)
    $before = @{}
    Get-ChildItem -LiteralPath $mockMusic -Recurse -File |
        Where-Object { $_.Name -ne 'wellerman.wav' } |
        ForEach-Object {
        $before[$_.FullName.Substring($mockMusic.Length)] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'install.ps1') `
        -GamePath $mockGame -SkipGameCheck -TestNoElevation
    Assert ($LASTEXITCODE -eq 0) 'Mock upgrade installer failed.'
    foreach ($relativePath in $before.Keys) {
        $afterPath = $mockMusic + $relativePath
        Assert (Test-Path -LiteralPath $afterPath) "Upgrade removed $relativePath"
        Assert ((Get-FileHash -LiteralPath $afterPath -Algorithm SHA256).Hash -eq $before[$relativePath]) "Upgrade changed $relativePath"
    }
    Assert (-not (Test-Path -LiteralPath (Join-Path $mockMusic 'wellerman.wav'))) 'Upgrade retained an exact legacy synthetic track.'
    Assert ((Get-FileHash -LiteralPath (Join-Path $mockMusic 'drunken_sailor.wav') -Algorithm SHA256).Hash -eq $before['\drunken_sailor.wav']) 'Upgrade removed a custom replacement that shares a legacy filename.'
    Assert ([IO.File]::ReadAllText($mockConfig).Trim() -eq $customConfigText) 'Upgrade did not preserve the custom boombox config.'
    Assert (Test-Path -LiteralPath (Join-Path $mockBoombox 'Scripts\main.lua')) 'Upgrade did not install PalBoombox code.'
    Assert (Test-Path -LiteralPath (Join-Path $mockMods 'PalSchema\mods\PalBoomboxItem\items\palboombox.json')) 'Upgrade did not install the boombox item.'

    Write-Host 'Building and inspecting the self-extracting installer...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'package.ps1')
    Assert ($LASTEXITCODE -eq 0) 'Installer build failed.'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $setupPath = Join-Path $repo 'PalWhip-Setup.exe'
    Assert (Test-Path -LiteralPath $setupPath) 'PalWhip-Setup.exe was not created.'
    $setupAssembly = [Reflection.Assembly]::LoadFile($setupPath)
    Assert ($setupAssembly.GetManifestResourceNames() -contains 'PalWhip.Payload.zip') 'Setup EXE is missing its embedded payload.'
    $payloadPath = Join-Path $tempRoot 'embedded-payload.zip'
    $payloadStream = $setupAssembly.GetManifestResourceStream('PalWhip.Payload.zip')
    try {
        $payloadFile = [IO.File]::Create($payloadPath)
        try { $payloadStream.CopyTo($payloadFile) } finally { $payloadFile.Dispose() }
    } finally {
        $payloadStream.Dispose()
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($payloadPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        Assert ($entryNames -contains 'install.ps1') 'Embedded payload is missing its installer logic.'
        Assert (-not ($entryNames -contains 'Install PalWhip.bat')) 'Embedded payload still exposes the old batch launcher.'
        Assert ($entryNames -contains 'PalBoombox/companion/control_panel.ps1') 'Package is missing the GUI.'
        Assert ($entryNames -contains 'PalBoombox/companion/import_music.ps1') 'Package is missing the importer.'
        Assert ($entryNames -contains 'PalBoomboxItem/resources/images/boombox-v2.png') 'Package is missing the current icon.'
        $runtimeEntries = @($entryNames | Where-Object {
            $_ -match '^PalBoombox/ipc/(state|companion|import_result|menu_command|menu_show|welcome_seen|whip_key|volume)\.txt$'
        })
        Assert ($runtimeEntries.Count -eq 0) 'Package contains runtime IPC files.'
        $expectedMusicEntries = @(
            'PalBoombox/music/Sail the Raging Sea (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Bully In The Alley (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Leave Her Johnny (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Maggie May (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Blow The Man Down (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Drunken Sailor (Sea Shanty) - Windrose.mp3'
        )
        $musicEntries = @($entryNames | Where-Object { $_ -match '^PalBoombox/music/' })
        Assert ($musicEntries.Count -eq 6) 'Package must contain exactly six bundled tracks.'
        foreach ($expectedMusicEntry in $expectedMusicEntries) {
            Assert ($entryNames -contains $expectedMusicEntry) "Package is missing bundled track: $expectedMusicEntry"
        }
        Assert (-not ($musicEntries | Where-Object { $_ -match '\.wav$' })) 'Package still contains a synthetic WAV track.'
        Assert (-not ($entryNames -contains 'tools/test_release.ps1')) 'Package unexpectedly contains development tools.'
    } finally {
        $archive.Dispose()
    }

    Write-Host 'All release regression checks passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
