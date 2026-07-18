# PalWhip + PalBoombox one-shot installer.
#
# Run this from the extracted mod zip (right-click -> Run with PowerShell).
# It will:
#   1. Find your Steam Palworld install (or ask you for the folder)
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
param([string]$GamePath, [switch]$SkipGameCheck)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$UE4SS_URL = 'https://github.com/Okaetsu/RE-UE4SS/releases/download/experimental-palworld/UE4SS-Palworld.zip'
$PALSCHEMA_API = 'https://api.github.com/repos/Okaetsu/PalSchema/releases/latest'
$PALSCHEMA_FALLBACK_URL = 'https://github.com/Okaetsu/PalSchema/releases/download/0.6.0/PalSchema_0.6.0.zip'

function Step($msg)  { Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "    $msg" -ForegroundColor Green }
function Skip($msg)  { Write-Host "    $msg (already installed, skipping)" -ForegroundColor DarkGray }
function Fail($msg)  { Write-Host "ERROR: $msg" -ForegroundColor Red; Read-Host 'Press Enter to exit'; exit 1 }

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
    Write-Host 'Could not find Palworld automatically.'
    $GamePath = Read-Host 'Paste your Palworld folder path (the one containing Pal and Palworld.exe)'
    if (-not (Test-Path (Join-Path $GamePath 'Pal\Binaries\Win64'))) {
        Fail "That doesn't look like a Palworld folder (no Pal\Binaries\Win64 inside)."
    }
}
Ok "Found: $GamePath"

if (-not $SkipGameCheck -and (Get-Process 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue)) {
    Fail 'Palworld is running. Close the game completely, then run this installer again.'
}

$w64 = Join-Path $GamePath 'Pal\Binaries\Win64'
$tmp = Join-Path $env:TEMP 'palwhip_installer'
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
Copy-Item (Join-Path $src 'PalWhip') $modsDir -Recurse -Force
Copy-Item (Join-Path $src 'PalBoombox') $modsDir -Recurse -Force
$schemaMods = Join-Path $palSchemaDir 'mods'
New-Item -ItemType Directory -Force $schemaMods | Out-Null
Copy-Item (Join-Path $src 'PalWhipItem') $schemaMods -Recurse -Force
Copy-Item (Join-Path $src 'PalBoomboxItem') $schemaMods -Recurse -Force
Ok 'Mods installed'

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
Write-Host '   Boombox:  craft at Primitive Workbench, press F9 to place, F10 = next song'
Write-Host '=============================================' -ForegroundColor Green
Read-Host 'Press Enter to close'
