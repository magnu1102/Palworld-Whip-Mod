# Safely removes PalWhip and Field Boombox without touching shared loaders,
# other mods, saves, or personal music/configuration backups.
param(
    [string]$GamePath,
    [string]$BackupPath,
    [switch]$AcknowledgeInGameCleanup,
    # Regression-test only: permits a disposable game tree under TEMP without UAC.
    [switch]$TestNoElevation
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Find-PalworldPath {
    $candidates = New-Object System.Collections.Generic.List[string]
    foreach ($registryPath in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )) {
        try {
            $steamInfo = Get-ItemProperty $registryPath -ErrorAction Stop
            $steamPath = $steamInfo.SteamPath
            if (-not $steamPath) { $steamPath = $steamInfo.InstallPath }
            if (-not $steamPath) { continue }
            $steamPath = $steamPath -replace '/', '\'
            $candidates.Add((Join-Path $steamPath 'steamapps\common\Palworld'))
            $libraryFile = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $libraryFile) {
                foreach ($match in (Select-String -LiteralPath $libraryFile -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches) {
                    $libraryPath = $match.Groups[1].Value -replace '\\\\', '\'
                    $candidates.Add((Join-Path $libraryPath 'steamapps\common\Palworld'))
                }
            }
        } catch {}
    }
    $candidates.Add('C:\Program Files (x86)\Steam\steamapps\common\Palworld')
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'Pal\Binaries\Win64')) {
            return $candidate
        }
    }
    return $null
}

if (-not $GamePath) { $GamePath = Find-PalworldPath }
if (-not $GamePath -or -not (Test-Path -LiteralPath (Join-Path $GamePath 'Pal\Binaries\Win64'))) {
    Fail 'Could not find Palworld. Run with -GamePath "D:\path\to\Palworld" if Steam uses an unusual location.'
}
$GamePath = [IO.Path]::GetFullPath($GamePath).TrimEnd('\')

if ($TestNoElevation) {
    $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not (($GamePath + '\').StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase))) {
        Fail '-TestNoElevation is restricted to disposable paths under TEMP.'
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdministrator -and -not $TestNoElevation) {
    $arguments = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-GamePath', ('"{0}"' -f $GamePath)
    )
    if ($BackupPath) { $arguments += @('-BackupPath', ('"{0}"' -f $BackupPath)) }
    if ($AcknowledgeInGameCleanup) { $arguments += '-AcknowledgeInGameCleanup' }
    try {
        $elevated = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
        exit $elevated.ExitCode
    } catch {
        Fail 'Administrator access is required to remove mods from the Palworld installation.'
    }
}

$runningGame = Get-Process -Name 'Palworld', 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue
if ($runningGame) {
    Fail 'Palworld is running. Close the game completely before uninstalling.'
}

if (-not $AcknowledgeInGameCleanup) {
    Write-Host ''
    Write-Host 'Before uninstalling, you must have:' -ForegroundColor Yellow
    Write-Host '  - dismantled every placed Field Boombox'
    Write-Host '  - discarded every Boombox and Pal Whip item'
    Write-Host '  - closed Palworld completely'
    Write-Host ''
    $answer = Read-Host 'Type UNINSTALL to confirm'
    if ($answer -cne 'UNINSTALL') {
        Write-Host 'Cancelled. Nothing was changed.' -ForegroundColor Yellow
        exit 2
    }
}

$modsRoot = [IO.Path]::GetFullPath((Join-Path $GamePath 'Pal\Binaries\Win64\ue4ss\Mods')).TrimEnd('\')
$targets = @(
    (Join-Path $modsRoot 'PalWhip'),
    (Join-Path $modsRoot 'PalBoombox'),
    (Join-Path $modsRoot 'PalSchema\mods\PalWhipItem'),
    (Join-Path $modsRoot 'PalSchema\mods\PalBoomboxItem')
)
$modsPrefix = $modsRoot + '\'
foreach ($target in $targets) {
    $resolvedTarget = [IO.Path]::GetFullPath($target).TrimEnd('\')
    if (-not (($resolvedTarget + '\').StartsWith($modsPrefix, [StringComparison]::OrdinalIgnoreCase))) {
        Fail "Refusing unsafe uninstall target: $resolvedTarget"
    }
}

$existingTargets = @($targets | Where-Object { Test-Path -LiteralPath $_ })
if ($existingTargets.Count -eq 0) {
    Write-Host 'PalWhip and Field Boombox are already uninstalled.' -ForegroundColor Green
    exit 0
}

if (-not $BackupPath) {
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $BackupPath = Join-Path $documents ("PalWhip Backups\Uninstall {0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$BackupPath = [IO.Path]::GetFullPath($BackupPath).TrimEnd('\')
foreach ($target in $targets) {
    $targetPrefix = [IO.Path]::GetFullPath($target).TrimEnd('\') + '\'
    if (($BackupPath + '\').StartsWith($targetPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Fail 'The backup folder cannot be inside a mod folder that will be removed.'
    }
}

$backupItems = @(
    @{
        Source = Join-Path $modsRoot 'PalWhip\Scripts\config.lua'
        Destination = Join-Path $BackupPath 'PalWhip\Scripts\config.lua'
    },
    @{
        Source = Join-Path $modsRoot 'PalBoombox\Scripts\config.lua'
        Destination = Join-Path $BackupPath 'PalBoombox\Scripts\config.lua'
    },
    @{
        Source = Join-Path $modsRoot 'PalBoombox\music'
        Destination = Join-Path $BackupPath 'PalBoombox\music'
    }
)
$backedUp = $false
foreach ($item in $backupItems) {
    if (-not (Test-Path -LiteralPath $item.Source)) { continue }
    $destinationParent = Split-Path $item.Destination -Parent
    New-Item -ItemType Directory -Force $destinationParent | Out-Null
    Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Recurse -Force
    $backedUp = $true
}

foreach ($target in $existingTargets) {
    $resolvedTarget = [IO.Path]::GetFullPath($target).TrimEnd('\')
    if (-not (($resolvedTarget + '\').StartsWith($modsPrefix, [StringComparison]::OrdinalIgnoreCase))) {
        Fail "Refusing unsafe uninstall target after resolution: $resolvedTarget"
    }
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
}

foreach ($target in $targets) {
    if (Test-Path -LiteralPath $target) {
        Fail "Could not completely remove: $target"
    }
}

Write-Host ''
Write-Host 'PalWhip and Field Boombox were removed successfully.' -ForegroundColor Green
Write-Host 'UE4SS, PalSchema, other mods, and Palworld saves were not changed.'
if ($backedUp) { Write-Host "Configuration and music backup: $BackupPath" }
Write-Host "You may now delete this uninstaller: $PSCommandPath"
