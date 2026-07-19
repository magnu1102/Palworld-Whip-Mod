# PalWhip + PalBoombox one-shot installer.
#
# Normally launched automatically from PalWhip-Setup.exe. This script can also
# be run directly from a source checkout for advanced/custom-path installs.
# It will:
#   1. Find your Steam Palworld install automatically
#   2. Download + install UE4SS (experimental-palworld build) if missing
#   3. Download + install PalSchema if missing
#   4. Apply the required UE4SS settings
#   5. Install the PalWhip / PalBoombox mods
#
# Everything comes from the official GitHub releases:
#   https://github.com/Okaetsu/RE-UE4SS   (UE4SS for Palworld)
#   https://github.com/Okaetsu/PalSchema  (PalSchema)
#
# Optional: .\install.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Palworld"
#           -SkipGameCheck  (install even while Palworld is running, e.g. to another copy)
param(
    [string]$GamePath,
    [switch]$SkipGameCheck,
    # Regression-test only: bypass UAC for a disposable game tree under TEMP.
    [switch]$TestNoElevation
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Installing into Program Files normally requires elevation. Relaunch this
# exact script as administrator and wait so the one-click launcher can report
# the real exit code when installation finishes.
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($TestNoElevation) {
    if (-not $GamePath) { throw '-TestNoElevation requires -GamePath.' }
    $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    $testGamePath = [IO.Path]::GetFullPath($GamePath).TrimEnd('\') + '\'
    if (-not $testGamePath.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw '-TestNoElevation is restricted to disposable paths under TEMP.'
    }
}
if (-not $isAdmin -and -not $TestNoElevation) {
    $elevatedArgs = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath)
    )
    if ($GamePath) {
        $elevatedArgs += '-GamePath'
        $elevatedArgs += ('"{0}"' -f $GamePath)
    }
    if ($SkipGameCheck) { $elevatedArgs += '-SkipGameCheck' }

    try {
        $elevated = Start-Process -FilePath 'powershell.exe' -Verb RunAs `
            -ArgumentList $elevatedArgs -Wait -PassThru
        exit $elevated.ExitCode
    } catch {
        Write-Host 'ERROR: Administrator access is required to install the mod.' -ForegroundColor Red
        exit 1
    }
}

$UE4SS_URL = 'https://github.com/Okaetsu/RE-UE4SS/releases/download/experimental-palworld/UE4SS-Palworld.zip'
$PALSCHEMA_API = 'https://api.github.com/repos/Okaetsu/PalSchema/releases/latest'
$PALSCHEMA_FALLBACK_URL = 'https://github.com/Okaetsu/PalSchema/releases/download/0.6.0/PalSchema_0.6.0.zip'

function Step($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }
function Skip($msg)  { Write-Host "    $msg (already installed, skipping)" -ForegroundColor DarkGray }
function Fail($msg)  { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# --- 0. Sanity: are the mod folders next to this script? -------------------
$src = $PSScriptRoot
$modFolders = 'PalWhip', 'PalBoombox', 'PalWhipItem', 'PalBoomboxItem'
foreach ($m in $modFolders) {
    if (-not (Test-Path (Join-Path $src $m))) {
        Fail "Folder '$m' not found next to install.ps1. Extract the WHOLE zip first, then run install.ps1 from the extracted folder."
    }
}

# --- 1. Find Palworld ------------------------------------------------------
Step 'Locating Palworld'
if (-not $GamePath) {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($regPath in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $steam = (Get-ItemProperty $regPath -ErrorAction Stop).SteamPath
            if (-not $steam) { $steam = (Get-ItemProperty $regPath -ErrorAction Stop).InstallPath }
            if ($steam) {
                $steam = $steam -replace '/', '\'
                $candidates.Add((Join-Path $steam 'steamapps\common\Palworld'))
                $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
                if (Test-Path $vdf) {
                    foreach ($m in (Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches) {
                        $lib = $m.Groups[1].Value -replace '\\\\', '\'
                        $candidates.Add((Join-Path $lib 'steamapps\common\Palworld'))
                    }
                }
            }
        } catch {}
    }
    $candidates.Add('C:\Program Files (x86)\Steam\steamapps\common\Palworld')
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c 'Pal\Binaries\Win64')) { $GamePath = $c; break }
    }
}
if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath 'Pal\Binaries\Win64'))) {
    Fail 'Could not find the Steam Palworld installation automatically. Advanced users can run install.ps1 with -GamePath "D:\path\to\Palworld".'
}
Ok "Found: $GamePath"

if (-not $SkipGameCheck -and (Get-Process 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue)) {
    Fail 'Palworld is running. Close the game completely, then run this installer again.'
}

$w64 = Join-Path $GamePath 'Pal\Binaries\Win64'
$tmp = Join-Path $env:TEMP ("palwhip_installer_{0}" -f [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $tmp | Out-Null

# --- 2. UE4SS --------------------------------------------------------------
Step 'UE4SS (experimental-palworld build)'
if (Test-Path (Join-Path $w64 'ue4ss\UE4SS.dll')) {
    Skip 'UE4SS'
} else {
    Ok 'Downloading UE4SS-Palworld.zip (~7 MB)...'
    $zip = Join-Path $tmp 'UE4SS-Palworld.zip'
    Invoke-WebRequest -Uri $UE4SS_URL -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $w64 -Force
    Ok 'UE4SS installed'
}
if (-not (Test-Path (Join-Path $w64 'dwmapi.dll'))) {
    Fail 'dwmapi.dll missing after UE4SS install - something went wrong, try again.'
}

# Required settings for Palworld
$ini = Join-Path $w64 'ue4ss\UE4SS-settings.ini'
if (Test-Path $ini) {
    $content = Get-Content $ini -Raw
    $orig = $content
    $content = $content -replace 'GraphicsAPI\s*=\s*opengl', 'GraphicsAPI = dx11'
    $content = $content -replace 'bUseUObjectArrayCache\s*=\s*true', 'bUseUObjectArrayCache = false'
    if ($content -ne $orig) {
        Set-Content $ini $content -NoNewline -Encoding utf8
        Ok 'UE4SS settings adjusted (dx11, UObjectArrayCache off)'
    } else {
        Ok 'UE4SS settings already correct'
    }
}

# --- 3. PalSchema ----------------------------------------------------------
Step 'PalSchema'
$modsDir = Join-Path $w64 'ue4ss\Mods'
$palSchemaDir = Join-Path $modsDir 'PalSchema'
if (Test-Path (Join-Path $palSchemaDir 'dlls\main.dll')) {
    Skip 'PalSchema'
} else {
    $url = $PALSCHEMA_FALLBACK_URL
    try {
        $release = Invoke-RestMethod $PALSCHEMA_API -Headers @{ 'User-Agent' = 'palwhip-installer' }
        $asset = $release.assets | Where-Object { $_.name -match '^PalSchema_[\d\.]+\.zip$' } | Select-Object -First 1
        if ($asset) { $url = $asset.browser_download_url }
    } catch {}
    Ok "Downloading $(Split-Path $url -Leaf) (~1 MB)..."
    $zip = Join-Path $tmp 'PalSchema.zip'
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    $extract = Join-Path $tmp 'palschema_x'
    if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
    Expand-Archive $zip -DestinationPath $extract -Force
    Copy-Item (Join-Path $extract 'PalSchema') $modsDir -Recurse -Force
    Ok 'PalSchema installed'
}

# --- 4. The mods -----------------------------------------------------------
Step 'PalWhip + PalBoombox mods'

$boomboxSource = Join-Path $src 'PalBoombox'
$boomboxTarget = Join-Path $modsDir 'PalBoombox'
$targetMusic = Join-Path $boomboxTarget 'music'

# v0.2.x used a separate WPF control panel, file picker, and command files.
# The native-building release has no visible companion UI. Remove only these
# known obsolete mod-owned files so an upgrade cannot leave the old window or
# command poller behind.
$obsoleteBoomboxFiles = @(
    'companion\control_panel.ps1',
    'companion\import_music.ps1',
    'ipc\import_result.txt',
    'ipc\menu_command.txt',
    'ipc\menu_show.txt',
    'ipc\welcome_seen.txt',
    'ipc\whip_key.txt'
)
# Previous releases shipped four generated WAV arrangements and two recordings
# that have now been replaced. Remove only byte-for-byte copies of those known
# release files. A user replacement with the same name but different content
# remains protected like every other personal file.
$legacyBundledMusic = [ordered]@{
    'bully_in_the_alley.wav' = '38C7486490D3FC1E4208856F66902306969D2C4686ECDC25E415367E208ABA89'
    'drunken_sailor.wav' = '5D7B2F3C1AAAC316DF2448FB7753BC8C287AB277B8B76D8C560B4327FBD3F192'
    'leave_her_johnny.wav' = '162D4FEB288D0A88BE2ABA644AAD086446D405BC80E7BAA3A15CE3442F370D1D'
    'wellerman.wav' = '0EBDEDB7BF21CFEF1820EBA10C90BFD158328D19827CDC507A530FDEB4AE0C7F'
    'Bully in the Alley - New Early Access Version  Windrose Sea Shanty & Lyrics.mp3' = '9135E30CA26329F8E7FBF3C3C4607956C2F0934A22479602D4A40D52BED7F469'
    'Leave Her Johnny - New Early Access Version  Windrose Sea Shanty & Lyrics.mp3' = '9E32040F696FD21C78DAFBE915238CDB0916FCAF40B1B0EDEE9E42DB107B8B90'
}
$legacyMusicToRemove = @()
if (Test-Path -LiteralPath $targetMusic) {
    foreach ($legacyName in $legacyBundledMusic.Keys) {
        $legacyPath = Join-Path $targetMusic $legacyName
        if ((Test-Path -LiteralPath $legacyPath) -and
            (Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256).Hash -eq $legacyBundledMusic[$legacyName]) {
            $legacyMusicToRemove += $legacyPath
        }
    }
}

# Snapshot every existing file in the personal music folder. The merge below
# never writes an existing music filename; this postcondition makes that
# promise executable and causes the installer to fail loudly if it is ever
# broken by a future change.
$existingMusic = @{}
if (Test-Path -LiteralPath $targetMusic) {
    $musicPrefix = $targetMusic.TrimEnd('\') + '\'
    Get-ChildItem -LiteralPath $targetMusic -Recurse -File |
        Where-Object { $_.FullName -notin $legacyMusicToRemove } |
        ForEach-Object {
        $relativePath = $_.FullName.Substring($musicPrefix.Length)
        $existingMusic[$relativePath] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    if ($existingMusic.Count -gt 0) {
        Ok "$($existingMusic.Count) existing music file(s) protected"
    }
}

# Keep user-edited settings across upgrades. New options still receive their
# defaults in Lua when they are absent from an older preserved config.
$preservedConfigs = @(
    @{
        Installed = Join-Path $modsDir 'PalWhip\Scripts\config.lua'
        Backup = Join-Path $tmp 'PalWhip-config.lua'
    },
    @{
        Installed = Join-Path $modsDir 'PalBoombox\Scripts\config.lua'
        Backup = Join-Path $tmp 'PalBoombox-config.lua'
    }
)
foreach ($configFile in $preservedConfigs) {
    if (Test-Path -LiteralPath $configFile.Installed) {
        Copy-Item -LiteralPath $configFile.Installed -Destination $configFile.Backup -Force
    }
}

$installSucceeded = $false
$removedLegacyBackups = @()
try {
if ($legacyMusicToRemove.Count -gt 0) {
    $legacyBackupDir = Join-Path $tmp 'legacy-music-backup'
    New-Item -ItemType Directory -Force $legacyBackupDir | Out-Null
    foreach ($legacyPath in $legacyMusicToRemove) {
        $backupPath = Join-Path $legacyBackupDir (Split-Path $legacyPath -Leaf)
        Copy-Item -LiteralPath $legacyPath -Destination $backupPath -Force
        $removedLegacyBackups += @{ Installed = $legacyPath; Backup = $backupPath }
        Remove-Item -LiteralPath $legacyPath -Force
    }
}

Copy-Item (Join-Path $src 'PalWhip') $modsDir -Recurse -Force

# Merge the boombox update without replacing any existing music file. This
# preserves imported songs and user replacements that share a bundled name.
New-Item -ItemType Directory -Force $boomboxTarget | Out-Null
Get-ChildItem -LiteralPath $boomboxSource -Force |
    Where-Object { $_.Name -ne 'music' } |
    ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $boomboxTarget -Recurse -Force
    }

$sourceMusic = Join-Path $boomboxSource 'music'
New-Item -ItemType Directory -Force $targetMusic | Out-Null
Get-ChildItem -LiteralPath $sourceMusic -File -ErrorAction SilentlyContinue |
    ForEach-Object {
        $destination = Join-Path $targetMusic $_.Name
        if (-not (Test-Path -LiteralPath $destination)) {
            Copy-Item -LiteralPath $_.FullName -Destination $destination
        }
    }

foreach ($relativePath in $existingMusic.Keys) {
    $preservedFile = Join-Path $targetMusic $relativePath
    if (-not (Test-Path -LiteralPath $preservedFile)) {
        Fail "Music preservation check failed: '$relativePath' was removed."
    }
    $preservedHash = (Get-FileHash -LiteralPath $preservedFile -Algorithm SHA256).Hash
    if ($preservedHash -ne $existingMusic[$relativePath]) {
        Fail "Music preservation check failed: '$relativePath' was changed."
    }
}
if ($existingMusic.Count -gt 0) {
    Ok 'Existing music verified unchanged'
}

$schemaMods = Join-Path $palSchemaDir 'mods'
New-Item -ItemType Directory -Force $schemaMods | Out-Null
Copy-Item (Join-Path $src 'PalWhipItem') $schemaMods -Recurse -Force
Copy-Item (Join-Path $src 'PalBoomboxItem') $schemaMods -Recurse -Force
$legacyBoomboxIcon = Join-Path $schemaMods 'PalBoomboxItem\resources\images\boombox.png'
if (Test-Path -LiteralPath $legacyBoomboxIcon) {
    Remove-Item -LiteralPath $legacyBoomboxIcon -Force
}
foreach ($relativeFile in $obsoleteBoomboxFiles) {
    $obsoletePath = Join-Path $boomboxTarget $relativeFile
    if (Test-Path -LiteralPath $obsoletePath) {
        Remove-Item -LiteralPath $obsoletePath -Force
    }
}
$installSucceeded = $true
} finally {
    if (-not $installSucceeded) {
        foreach ($legacyBackup in $removedLegacyBackups) {
            Copy-Item -LiteralPath $legacyBackup.Backup -Destination $legacyBackup.Installed -Force
        }
    }
    # A failed dependency/mod copy must never strand the bundled config over
    # the user's settings. PowerShell executes finally even during exit/error.
    foreach ($configFile in $preservedConfigs) {
        if (Test-Path -LiteralPath $configFile.Backup) {
            Copy-Item -LiteralPath $configFile.Backup -Destination $configFile.Installed -Force
        }
    }
}
Ok 'Mods installed'
if ($legacyMusicToRemove.Count -gt 0) {
    Ok "$($legacyMusicToRemove.Count) obsolete synthetic track(s) removed"
}
Ok 'Existing settings and custom music preserved'

$music = Join-Path $modsDir 'PalBoombox\music'
$trackCount = 0
if (Test-Path $music) {
    $trackCount = (Get-ChildItem $music -File | Where-Object { $_.Extension -in '.wav', '.mp3', '.wma' }).Count
}
if ($trackCount -eq 0) {
    Write-Host '    NOTE: no music files found in PalBoombox\music - the boombox will be silent until you add some.' -ForegroundColor Yellow
} else {
    Ok "$trackCount boombox track(s) ready"
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '=============================================' -ForegroundColor Green
Write-Host ' Done! Launch Palworld and enjoy:' -ForegroundColor Green
Write-Host '   Pal Whip: craft at Primitive Workbench, equip, press F7'
Write-Host '   Boombox: craft it, then place Field Boombox from the build menu'
Write-Host '   Volume:   F5 = down, F6 = up (local listening volume)'
Write-Host '=============================================' -ForegroundColor Green
