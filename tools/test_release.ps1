$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$tempRoot = Join-Path $env:TEMP ("palwhip_release_test_{0}" -f [Guid]::NewGuid().ToString('N'))
$utf8NoBom = New-Object Text.UTF8Encoding($false)

function Assert([bool]$condition, [string]$message) {
    if (-not $condition) { throw "ASSERTION FAILED: $message" }
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

    Write-Host 'Checking downloadable uninstaller launcher...'
    $uninstallerLauncherText = [IO.File]::ReadAllText((Join-Path $repo 'Uninstall-PalWhip.cmd'))
    Assert ($uninstallerLauncherText.Contains('-ExecutionPolicy Bypass')) 'Uninstaller launcher does not bypass RemoteSigned for the downloaded PS1.'
    Assert ($uninstallerLauncherText.Contains('if not defined PALWHIP_UNINSTALL_NO_PAUSE pause')) 'Uninstaller launcher can close before showing its result.'

    Write-Host 'Checking downloadable installer launcher...'
    $installerLauncherText = [IO.File]::ReadAllText((Join-Path $repo 'Install-PalWhip.cmd'))
    Assert ($installerLauncherText.Contains('-ExecutionPolicy Bypass')) 'Installer launcher does not bypass RemoteSigned for the downloaded PS1.'
    Assert ($installerLauncherText.Contains('if not defined PALWHIP_INSTALL_NO_PAUSE pause')) 'Installer launcher can close before showing its result.'

    Write-Host 'Checking live-game update protection...'
    $installerText = [IO.File]::ReadAllText((Join-Path $repo 'install.ps1'))
    $runningGameGuard = $installerText.IndexOf("Get-Process 'Palworld-Win64-Shipping'")
    $firstModCopy = $installerText.IndexOf("Copy-Item (Join-Path `$src 'PalWhip')")
    Assert ($runningGameGuard -ge 0) 'Installer does not reject updates while Palworld is running.'
    Assert ($firstModCopy -gt $runningGameGuard) 'Installer can copy mod files before checking whether Palworld is running.'

    Write-Host 'Checking Lua syntax...'
    $npx = Get-Command npx -ErrorAction SilentlyContinue
    Assert ($null -ne $npx) 'npx is required for the Lua syntax regression check.'
    foreach ($luaFile in (Get-ChildItem -LiteralPath (Join-Path $repo 'PalWhip'), (Join-Path $repo 'PalBoombox') -Recurse -Filter '*.lua')) {
        & npx --yes luaparse $luaFile.FullName | Out-Null
        Assert ($LASTEXITCODE -eq 0) "Lua parse failed: $($luaFile.FullName)"
    }

    Write-Host 'Checking item JSON...'
    Get-ChildItem -LiteralPath (Join-Path $repo 'PalWhipItem'), (Join-Path $repo 'PalBoomboxItem') -Recurse -Filter '*.json' |
        ForEach-Object { [void](Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json) }

    Write-Host 'Checking native building placement and crash-capable calls...'
    $boomboxLua = [IO.File]::ReadAllText((Join-Path $repo 'PalBoombox\Scripts\main.lua'))
    foreach ($unsafeText in 'SpawnActorBroadcast', 'BeginDeferredActorSpawnFromClass', 'FinishSpawningActor', 'EnterChat', 'BroadcastChatMessage') {
        Assert (-not $boomboxLua.Contains($unsafeText)) "Unsafe marker code remains: $unsafeText"
    }
    Assert ($boomboxLua.Contains('FindAllOf("PalBuildObject")')) 'Lua does not discover the native replicated building.'
    Assert ($boomboxLua.Contains('actor.BuildObjectId:ToString()')) 'Lua does not verify the custom building identity.'
    Assert ($boomboxLua.Contains('ExecuteInGameThread(function()')) 'Async spatial loop does not marshal UObject access to the game thread.'
    Assert (-not $boomboxLua.Contains('PalInteractiveObjectComponentInterface:GetIndicatorInfo')) 'Crash-prone native interaction hook was reintroduced.'
    Assert (-not $boomboxLua.Contains('PalBuildObject:OnTriggerInteractBuilding')) 'Crash-prone building interaction hook was reintroduced.'
    Assert ($boomboxLua.Contains('local PAUSE_KEY = config.PauseKey or "F8"')) 'Pause/resume hotkey is missing.'
    Assert ($boomboxLua.Contains('if NEXT_TRACK_KEY == nil or NEXT_TRACK_KEY == "F10" then NEXT_TRACK_KEY = "F9" end')) 'Legacy F10 next-track binding is not migrated safely.'
    Assert ($boomboxLua.Contains('stationPausedCursor')) 'Pause does not freeze the deterministic station clock.'
    Assert ($boomboxLua.Contains('local nextCursor = playlistStart(nextIndex)')) 'Next Track does not seek to the following song boundary.'
    Assert ($boomboxLua.Contains('distance <= REF_DISTANCE')) 'Spatial audio no longer has a full-volume near field.'
    Assert ($boomboxLua.Contains('fade ^ FADE_EXPONENT')) 'Spatial audio does not use the gradual configurable fade.'
    Assert ($boomboxLua.Contains('progress * progress * (3.0 - 2.0 * progress)')) 'Spatial audio outer boundary does not use a zero-slope smoothstep tail.'
    Assert ($boomboxLua.Contains('config.FadeExponent or 0.65, 0.55, 2.0')) 'Fade exponent can still create an abrupt outer endpoint.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $repo 'PalBoombox\companion\control_panel.ps1'))) 'External control panel still exists.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $repo 'PalBoombox\companion\import_music.ps1'))) 'External music picker still exists.'

    $buildingFile = Join-Path $repo 'PalBoomboxItem\buildings\palboombox.json'
    $buildingRoot = Get-Content -LiteralPath $buildingFile -Raw | ConvertFrom-Json
    $building = $buildingRoot.PalBoombox
    Assert ($building.BlueprintClassSoft -eq '/Game/Pal/Blueprint/MapObject/BuildObject/Furniture/BP_BuildObject_Television01_Iron.BP_BuildObject_Television01_Iron_C') 'Building does not use the reviewed native electronic prop.'
    Assert ($building.BuildingData.TypeA -eq 'Furniture') 'Building is not registered in the native furniture category.'
    Assert ($building.BuildingData.Material1_Id -eq 'PalBoombox') 'Building no longer consumes the crafted boombox item.'
    Assert ($building.Technology.UnlockBuildObjects -contains 'PalBoombox') 'Building is not unlocked in the Technology/build UI.'

    Write-Host 'Checking persistent layered volume controls...'
    Assert ($boomboxLua.Contains('ipc/volume.txt')) 'Listening volume is not persisted between sessions.'
    Assert ($boomboxLua.Contains('VolumeDownKey')) 'Local volume-down hotkey is missing.'
    Assert ($boomboxLua.Contains('VolumeUpKey')) 'Local volume-up hotkey is missing.'
    $companionText = [IO.File]::ReadAllText((Join-Path $repo 'PalBoombox\companion\boombox_companion.ps1'))
    Assert ($companionText.Contains('$maxLayers = 3')) 'Actual volume gain layers are missing.'
    Assert ($companionText.Contains("`$candidate['seq'] -eq `$candidate['commit']")) 'Companion does not reject partial IPC snapshots.'
    Assert ($companionText.Contains('[IO.FileShare]::ReadWrite')) 'Companion state reads can still block Lua writes.'
    Assert ($companionText.Contains('$warmupUntilMs')) 'Track startup does not warm and align decoder layers.'
    Assert ($boomboxLua.Contains('launch_hidden.vbs')) 'Lua does not use the windowless companion launcher.'

    Write-Host 'Checking deterministic clock-synchronized playlist...'
    Assert ($boomboxLua.Contains('shared_playlist.txt')) 'Lua does not load the deterministic shared playlist.'
    Assert ($boomboxLua.Contains('(clock + stationClockOffset) % playlistDuration')) 'Lua does not derive playback from the shared clock and station controls.'
    $bundledManifest = @(
        Get-Content -LiteralPath (Join-Path $repo 'PalBoombox\bundled_tracks.txt') -Encoding UTF8 |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    Assert ($bundledManifest.Count -eq 9) 'Bundled-track manifest must contain exactly nine filenames.'
    $playlistRows = @(
        Get-Content -LiteralPath (Join-Path $repo 'PalBoombox\shared_playlist.txt') -Encoding UTF8 |
            Where-Object { $_ -and -not $_.StartsWith('#') }
    )
    Assert ($playlistRows.Count -eq 9) 'Shared playlist must contain exactly nine timed tracks.'
    foreach ($row in $playlistRows) {
        $parts = $row -split '\|', 2
        Assert ($parts.Count -eq 2 -and [double]::Parse($parts[0], [Globalization.CultureInfo]::InvariantCulture) -gt 1) "Invalid shared playlist row: $row"
        Assert ($bundledManifest -contains $parts[1]) "Shared playlist uses a non-bundled track: $($parts[1])"
    }

    Write-Host 'Testing culture-invariant companion values...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
        (Join-Path $repo 'PalBoombox\companion\boombox_companion.ps1') -ValidateOnly
    Assert ($LASTEXITCODE -eq 0) 'Companion invariant-number self-test failed.'

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
    New-Item -ItemType Directory -Force (Join-Path $mockBoombox 'companion'), (Join-Path $mockBoombox 'ipc') | Out-Null
    [IO.File]::WriteAllText((Join-Path $mockBoombox 'companion\control_panel.ps1'), 'legacy external UI', $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $mockBoombox 'companion\import_music.ps1'), 'legacy picker', $utf8NoBom)
    [IO.File]::WriteAllText((Join-Path $mockBoombox 'ipc\menu_command.txt'), 'legacy command', $utf8NoBom)
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
    Assert (Test-Path -LiteralPath (Join-Path $mockMods 'PalSchema\mods\PalBoomboxItem\buildings\palboombox.json')) 'Upgrade did not install the native boombox building.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $mockBoombox 'companion\control_panel.ps1'))) 'Upgrade retained the obsolete external control panel.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $mockBoombox 'companion\import_music.ps1'))) 'Upgrade retained the obsolete file picker.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $mockBoombox 'ipc\menu_command.txt'))) 'Upgrade retained obsolete panel IPC.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $mockMods 'PalSchema\mods\PalBoomboxItem\resources\images\boombox.png'))) 'Upgrade retained the obsolete boombox icon.'
    Assert (Test-Path -LiteralPath (Join-Path $mockGame 'Uninstall-PalWhip.ps1')) 'Installer did not place the uninstaller in the Palworld folder.'
    Assert (Test-Path -LiteralPath (Join-Path $mockGame 'Uninstall-PalWhip.cmd')) 'Installer did not place the uninstaller launcher in the Palworld folder.'

    Write-Host 'Testing scoped uninstall, backup, and shared-loader preservation...'
    $mockWhipConfig = Join-Path $mockMods 'PalWhip\Scripts\config.lua'
    $customWhipConfigText = 'return { HealHP = false }'
    [IO.File]::WriteAllText($mockWhipConfig, $customWhipConfigText, $utf8NoBom)
    $unrelatedMod = Join-Path $mockMods 'OtherMod'
    New-Item -ItemType Directory -Force $unrelatedMod | Out-Null
    [IO.File]::WriteAllText((Join-Path $unrelatedMod 'keep.txt'), 'unrelated mod', $utf8NoBom)
    $uninstallBackup = Join-Path $tempRoot 'uninstall-backup'
    $musicBeforeUninstall = @{}
    Get-ChildItem -LiteralPath $mockMusic -Recurse -File | ForEach-Object {
        $relativeName = $_.FullName.Substring($mockMusic.Length).TrimStart('\')
        $musicBeforeUninstall[$relativeName] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }

    $previousNoPause = $env:PALWHIP_UNINSTALL_NO_PAUSE
    try {
        $env:PALWHIP_UNINSTALL_NO_PAUSE = '1'
        & (Join-Path $repo 'Uninstall-PalWhip.cmd') `
            -GamePath $mockGame -BackupPath $uninstallBackup `
            -AcknowledgeInGameCleanup -TestNoElevation
        $uninstallExitCode = $LASTEXITCODE
    } finally {
        $env:PALWHIP_UNINSTALL_NO_PAUSE = $previousNoPause
    }
    Assert ($uninstallExitCode -eq 0) 'Mock uninstall through the CMD launcher failed.'
    foreach ($removedTarget in @(
        (Join-Path $mockMods 'PalWhip'),
        (Join-Path $mockMods 'PalBoombox'),
        (Join-Path $mockMods 'PalSchema\mods\PalWhipItem'),
        (Join-Path $mockMods 'PalSchema\mods\PalBoomboxItem')
    )) {
        Assert (-not (Test-Path -LiteralPath $removedTarget)) "Uninstaller retained mod target: $removedTarget"
    }
    Assert (Test-Path -LiteralPath (Join-Path $mockWin64 'ue4ss\UE4SS.dll')) 'Uninstaller removed the shared UE4SS loader.'
    Assert (Test-Path -LiteralPath (Join-Path $mockMods 'PalSchema\dlls\main.dll')) 'Uninstaller removed the shared PalSchema loader.'
    Assert ([IO.File]::ReadAllText((Join-Path $unrelatedMod 'keep.txt')).Trim() -eq 'unrelated mod') 'Uninstaller changed an unrelated mod.'
    Assert ([IO.File]::ReadAllText((Join-Path $uninstallBackup 'PalWhip\Scripts\config.lua')).Trim() -eq $customWhipConfigText) 'Uninstaller did not back up PalWhip configuration.'
    Assert ([IO.File]::ReadAllText((Join-Path $uninstallBackup 'PalBoombox\Scripts\config.lua')).Trim() -eq $customConfigText) 'Uninstaller did not back up PalBoombox configuration.'
    foreach ($relativeName in $musicBeforeUninstall.Keys) {
        $backupMusicFile = Join-Path (Join-Path $uninstallBackup 'PalBoombox\music') $relativeName
        Assert (Test-Path -LiteralPath $backupMusicFile) "Uninstaller did not back up music file: $relativeName"
        Assert ((Get-FileHash -LiteralPath $backupMusicFile -Algorithm SHA256).Hash -eq $musicBeforeUninstall[$relativeName]) "Uninstaller changed backed-up music file: $relativeName"
    }

    Write-Host 'Building and inspecting all release artifacts...'
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
        Assert ($entryNames -contains 'Install-PalWhip.cmd') 'Embedded payload is missing the PowerShell installer launcher.'
        Assert ($entryNames -contains 'Uninstall-PalWhip.ps1') 'Embedded payload is missing the uninstaller.'
        Assert ($entryNames -contains 'Uninstall-PalWhip.cmd') 'Embedded payload is missing the uninstaller launcher.'
        Assert (-not ($entryNames -contains 'Install PalWhip.bat')) 'Embedded payload still exposes the old batch launcher.'
        Assert (-not ($entryNames -contains 'PalBoombox/companion/control_panel.ps1')) 'Package still contains the external GUI.'
        Assert (-not ($entryNames -contains 'PalBoombox/companion/import_music.ps1')) 'Package still contains the external picker.'
        Assert ($entryNames -contains 'PalBoombox/bundled_tracks.txt') 'Package is missing the shared-track manifest.'
        Assert ($entryNames -contains 'PalBoombox/shared_playlist.txt') 'Package is missing the timed shared playlist.'
        Assert ($entryNames -contains 'PalBoomboxItem/buildings/palboombox.json') 'Package is missing the native building definition.'
        Assert ($entryNames -contains 'PalBoomboxItem/resources/images/boombox-v2.png') 'Package is missing the current icon.'
        Assert (-not ($entryNames -contains 'PalBoomboxItem/resources/images/boombox.png')) 'Package still contains the obsolete icon.'
        $runtimeEntries = @($entryNames | Where-Object {
            $_ -match '^PalBoombox/ipc/(state|companion|volume)\.txt$'
        })
        Assert ($runtimeEntries.Count -eq 0) 'Package contains runtime IPC files.'
        $expectedMusicEntries = @(
            'PalBoombox/music/Sail the Raging Sea (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Bully In The Alley (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Leave Her Johnny (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Maggie May (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Blow The Man Down (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/Drunken Sailor (Sea Shanty) - Windrose.mp3',
            'PalBoombox/music/12 Years a Slave 2013   Roll Jordan Roll.mp3',
            'PalBoombox/music/Down to the River to Pray.mp3',
            'PalBoombox/music/gonna see miss liza....mp3'
        )
        $musicEntries = @($entryNames | Where-Object { $_ -match '^PalBoombox/music/' })
        Assert ($musicEntries.Count -eq 9) 'Package must contain exactly nine bundled tracks.'
        foreach ($expectedMusicEntry in $expectedMusicEntries) {
            Assert ($entryNames -contains $expectedMusicEntry) "Package is missing bundled track: $expectedMusicEntry"
        }
        Assert (-not ($musicEntries | Where-Object { $_ -match '\.wav$' })) 'Package still contains a synthetic WAV track.'
        Assert (-not ($entryNames -contains 'tools/test_release.ps1')) 'Package unexpectedly contains development tools.'
    } finally {
        $archive.Dispose()
    }

    $installerZipPath = Join-Path $repo 'PalWhip-Installer.zip'
    Assert (Test-Path -LiteralPath $installerZipPath) 'PalWhip-Installer.zip was not created.'
    $installerZipArchive = [IO.Compression.ZipFile]::OpenRead($installerZipPath)
    try {
        $installerZipEntries = @($installerZipArchive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        foreach ($expectedInstallerEntry in @(
            'install.ps1',
            'Install-PalWhip.cmd',
            'INSTALL-README.txt',
            'PalWhip/Scripts/main.lua',
            'PalBoombox/Scripts/main.lua',
            'PalWhipItem/items/palwhip.json',
            'PalBoomboxItem/buildings/palboombox.json',
            'Uninstall-PalWhip.ps1',
            'Uninstall-PalWhip.cmd'
        )) {
            Assert ($installerZipEntries -contains $expectedInstallerEntry) "PowerShell installer ZIP is missing: $expectedInstallerEntry"
        }
        $installerZipMusic = @($installerZipEntries | Where-Object { $_ -match '^PalBoombox/music/.+\.mp3$' })
        Assert ($installerZipMusic.Count -eq 9) 'PowerShell installer ZIP must contain exactly nine bundled tracks.'
        $installerZipRuntime = @($installerZipEntries | Where-Object { $_ -match '^PalBoombox/ipc/(state|companion|volume)\.txt$' })
        Assert ($installerZipRuntime.Count -eq 0) 'PowerShell installer ZIP contains runtime IPC files.'
    } finally {
        $installerZipArchive.Dispose()
    }

    $manualPath = Join-Path $repo 'PalWhip-Manual.zip'
    Assert (Test-Path -LiteralPath $manualPath) 'PalWhip-Manual.zip was not created.'
    $manualArchive = [IO.Compression.ZipFile]::OpenRead($manualPath)
    try {
        $manualEntries = @($manualArchive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        Assert ($manualEntries -contains 'MANUAL-INSTALL.txt') 'Manual archive is missing its instructions.'
        Assert ($manualEntries -contains 'Uninstall-PalWhip.ps1') 'Manual archive is missing the uninstaller.'
        Assert ($manualEntries -contains 'Uninstall-PalWhip.cmd') 'Manual archive is missing the uninstaller launcher.'
        Assert ($manualEntries -contains 'Pal/Binaries/Win64/ue4ss/Mods/PalWhip/Scripts/main.lua') 'Manual archive is missing PalWhip.'
        Assert ($manualEntries -contains 'Pal/Binaries/Win64/ue4ss/Mods/PalBoombox/Scripts/main.lua') 'Manual archive is missing PalBoombox.'
        Assert ($manualEntries -contains 'Pal/Binaries/Win64/ue4ss/Mods/PalSchema/mods/PalWhipItem/items/palwhip.json') 'Manual archive is missing PalWhipItem.'
        Assert ($manualEntries -contains 'Pal/Binaries/Win64/ue4ss/Mods/PalSchema/mods/PalBoomboxItem/buildings/palboombox.json') 'Manual archive is missing the Field Boombox building.'
        Assert (-not ($manualEntries | Where-Object { $_ -match '\.(exe|bat)$' -or $_ -match '(^|/)install\.ps1$' })) 'Manual archive contains an executable or installer script.'
        Assert (-not ($manualEntries -contains 'Pal/Binaries/Win64/ue4ss/Mods/PalWhip/Scripts/config.lua')) 'Manual archive would overwrite PalWhip settings.'
        Assert (-not ($manualEntries -contains 'Pal/Binaries/Win64/ue4ss/Mods/PalBoombox/Scripts/config.lua')) 'Manual archive would overwrite PalBoombox settings.'
        $manualRuntime = @($manualEntries | Where-Object { $_ -match '/PalBoombox/ipc/(state|companion|volume)\.txt$' })
        Assert ($manualRuntime.Count -eq 0) 'Manual archive contains runtime IPC files.'
        $manualMusic = @($manualEntries | Where-Object { $_ -match '/PalBoombox/music/.+\.mp3$' })
        Assert ($manualMusic.Count -eq 9) 'Manual archive must contain exactly nine bundled tracks.'
    } finally {
        $manualArchive.Dispose()
    }

    $uninstallerPath = Join-Path $repo 'PalWhip-Uninstaller.zip'
    Assert (Test-Path -LiteralPath $uninstallerPath) 'PalWhip-Uninstaller.zip was not created.'
    $uninstallerArchive = [IO.Compression.ZipFile]::OpenRead($uninstallerPath)
    try {
        $uninstallerEntries = @($uninstallerArchive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
        Assert ($uninstallerEntries.Count -eq 3) 'Standalone uninstaller ZIP contains unexpected files.'
        foreach ($expectedUninstallerEntry in 'Uninstall-PalWhip.ps1', 'Uninstall-PalWhip.cmd', 'UNINSTALL-README.txt') {
            Assert ($uninstallerEntries -contains $expectedUninstallerEntry) "Standalone uninstaller ZIP is missing: $expectedUninstallerEntry"
        }
    } finally {
        $uninstallerArchive.Dispose()
    }

    Write-Host 'All release regression checks passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
