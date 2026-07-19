# PalBoombox hidden audio companion.
#
# Palworld cannot decode arbitrary MP3 files through Wwise, so the UE4SS Lua
# layer writes spatial state to this process. This process has no visible UI.
# It uses up to three synchronized MediaPlayer layers so requested volume above
# 100% produces real gain rather than being silently clipped at 1.0.
param([switch]$ValidateOnly)

$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationCore

$root = Split-Path $PSScriptRoot -Parent
$musicDir = Join-Path $root 'music'
$ipcDir = Join-Path $root 'ipc'
$stateFile = Join-Path $ipcDir 'state.txt'
$companionFile = Join-Path $ipcDir 'companion.txt'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$invariantCulture = [Globalization.CultureInfo]::InvariantCulture
$maxLayers = 3
New-Item -ItemType Directory -Force $ipcDir | Out-Null

function Get-Epoch { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function ConvertFrom-InvariantDouble([string]$text, [double]$fallback) {
    $parsed = 0.0
    if ([double]::TryParse(
        $text,
        [Globalization.NumberStyles]::Float,
        $invariantCulture,
        [ref]$parsed)) {
        return $parsed
    }
    return $fallback
}

function Get-LayerVolumes([double]$requestedVolume) {
    $remaining = [math]::Max(0.0, [math]::Min([double]$maxLayers, $requestedVolume))
    $result = @()
    for ($index = 0; $index -lt $maxLayers; $index++) {
        $layer = [math]::Min(1.0, $remaining)
        $result += $layer
        $remaining -= $layer
    }
    return $result
}

if ($ValidateOnly) {
    $originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
    try {
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('nb-NO')
        $parsed = ConvertFrom-InvariantDouble '1.500' -1.0
        $formatted = ([double]1.5).ToString('0.000', $invariantCulture)
        $layers = @(Get-LayerVolumes 2.25)
        if ($parsed -ne 1.5 -or $formatted -ne '1.500' -or
            $layers.Count -ne 3 -or $layers[0] -ne 1.0 -or
            $layers[1] -ne 1.0 -or $layers[2] -ne 0.25) {
            Write-Error 'Invariant parsing or layered gain validation failed.'
            exit 1
        }
    } finally {
        [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
    }
    Write-Output 'PalBoombox companion validation: OK'
    exit 0
}

# A second copy exits quietly; every local player needs exactly one audio
# engine even if Lua retries startup while PowerShell is still initializing.
$mutex = New-Object System.Threading.Mutex($false, 'PalBoomboxCompanion')
if (-not $mutex.WaitOne(0)) { exit }

$players = @()
for ($index = 0; $index -lt $maxLayers; $index++) {
    $players += New-Object System.Windows.Media.MediaPlayer
}

$currentTrack = ''
$lastHeartbeat = 0
$lastGameCheck = 0
$appliedSeekSeq = ''
$pendingSeek = -1.0
$lastValidState = @{}
$trackReady = $false
$warmupUntilMs = 0L

function Write-Heartbeat {
    $position = if ($players.Count -gt 0) { $players[0].Position.TotalSeconds } else { 0.0 }
    $formattedPosition = ([math]::Round([double]$position, 1)).ToString('0.0', $invariantCulture)
    $lines = @(
        "alive=$(Get-Epoch)",
        "current=$currentTrack",
        "pos=$formattedPosition"
    )
    [IO.File]::WriteAllText($companionFile, ($lines -join "`n"), $utf8NoBom)
}

function Read-CommittedState {
    $candidate = @{}
    $raw = @()
    if (Test-Path -LiteralPath $stateFile) {
        # ReadAllText opens with FileShare.Read and can briefly block Lua's
        # writer. Share both read and write instead; seq/commit validation
        # below already guarantees that a concurrent partial read is ignored.
        $stream = $null
        $reader = $null
        try {
            $stream = [IO.File]::Open(
                $stateFile,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::ReadWrite
            )
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true, 1024, $true)
            $raw = $reader.ReadToEnd() -split "`r?`n"
        } catch {
            return $null
        } finally {
            if ($null -ne $reader) { $reader.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
    foreach ($line in $raw) {
        $pair = $line -split '=', 2
        if ($pair.Count -eq 2) { $candidate[$pair[0].Trim()] = $pair[1].Trim() }
    }
    if ($candidate['seq'] -and $candidate['seq'] -eq $candidate['commit']) {
        return $candidate
    }
    return $null
}

function Stop-AllPlayers {
    foreach ($mediaPlayer in $players) { $mediaPlayer.Stop() }
}

function Open-Track([string]$trackPath) {
    foreach ($mediaPlayer in $players) {
        $mediaPlayer.Volume = 0.0
        $mediaPlayer.Open([Uri]$trackPath)
        $mediaPlayer.Pause()
    }
}

function Set-AllPositions([double]$seconds) {
    $position = [TimeSpan]::FromSeconds([math]::Max(0.0, $seconds))
    foreach ($mediaPlayer in $players) { $mediaPlayer.Position = $position }
}

function Play-AllPlayers {
    foreach ($mediaPlayer in $players) { $mediaPlayer.Play() }
}

Write-Heartbeat

while ($true) {
    Start-Sleep -Milliseconds 100

    $committed = Read-CommittedState
    if ($null -ne $committed) { $lastValidState = $committed }
    $state = $lastValidState

    if ($state['quit'] -eq '1') { break }

    $playing = $state['playing'] -eq '1'
    $track = $state['track']

    if ($playing -and $track) {
        $trackPath = Join-Path $musicDir $track
        if (($track -ne $currentTrack) -and (Test-Path -LiteralPath $trackPath)) {
            Open-Track $trackPath
            $currentTrack = $track
            $pendingSeek = -1.0
            $trackReady = $false
            $warmupUntilMs = 0L
        }

        if ($state['seekseq'] -and $state['seekseq'] -ne $appliedSeekSeq) {
            $appliedSeekSeq = $state['seekseq']
            $pendingSeek = ConvertFrom-InvariantDouble $state['seek'] -1.0
        }

        $primary = $players[0]
        if ($pendingSeek -ge 0 -and $primary.NaturalDuration.HasTimeSpan) {
            $duration = $primary.NaturalDuration.TimeSpan.TotalSeconds
            if ($duration -gt 1) {
                Set-AllPositions ($pendingSeek % $duration)
                # Prime every decoder while muted. The final alignment below
                # happens after buffers are warm, avoiding the brief layered
                # burst/seek stutter that otherwise occurs at track startup.
                Play-AllPlayers
                $warmupUntilMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 500
            }
            $pendingSeek = -1.0
        }

        if (-not $trackReady -and $warmupUntilMs -gt 0 -and
            [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() -ge $warmupUntilMs) {
            $alignedPosition = $primary.Position.TotalSeconds
            Set-AllPositions $alignedPosition
            Play-AllPlayers
            $trackReady = $true
            $warmupUntilMs = 0L
        }

        $requestedVolume = ConvertFrom-InvariantDouble $state['volume'] 0.0
        $balance = ConvertFrom-InvariantDouble $state['balance'] 0.0
        $layerVolumes = @(Get-LayerVolumes $requestedVolume)
        for ($index = 0; $index -lt $players.Count; $index++) {
            $players[$index].Volume = if ($trackReady) { $layerVolumes[$index] } else { 0.0 }
            $players[$index].Balance = [math]::Max(-1.0, [math]::Min(1.0, $balance))
        }

        if ($trackReady -and $primary.NaturalDuration.HasTimeSpan) {
            $duration = $primary.NaturalDuration.TimeSpan.TotalSeconds
            if ($duration -gt 0 -and $primary.Position.TotalSeconds -ge $duration - 0.3) {
                Set-AllPositions 0.0
                Play-AllPlayers
            }
        }
    } elseif ($currentTrack -ne '') {
        Stop-AllPlayers
        $currentTrack = ''
        $trackReady = $false
        $warmupUntilMs = 0L
    }

    $now = Get-Epoch
    if ($now - $lastHeartbeat -ge 2) {
        Write-Heartbeat
        $lastHeartbeat = $now
    }

    if ($now - $lastGameCheck -ge 5) {
        $lastGameCheck = $now
        if (-not (Get-Process 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue)) { break }
    }
}

Stop-AllPlayers
foreach ($mediaPlayer in $players) { $mediaPlayer.Close() }
Remove-Item -LiteralPath $companionFile -ErrorAction SilentlyContinue
$mutex.ReleaseMutex()
