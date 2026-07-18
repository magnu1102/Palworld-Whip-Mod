# PalBoombox audio companion.
# Plays the boombox track with volume + stereo balance driven by the PalBoombox
# UE4SS Lua mod, which writes ..\ipc\state.txt ~10x/second based on where the
# player is relative to the placed boombox. Pure PowerShell + WPF MediaPlayer;
# no dependencies. Started automatically by the mod (or run it manually).
#
# Protocol (key=value lines):
#   state.txt  (mod -> companion): playing=0|1, track=<file>, volume=0..1,
#              balance=-1..1, seek=<seconds>, seekseq=<id>, quit=1
#   companion.txt (companion -> mod): alive=<unix time>, pos=<seconds>,
#              track=<file> (one line per available track in ..\music)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationCore

$root     = Split-Path $PSScriptRoot -Parent
$musicDir = Join-Path $root 'music'
$ipcDir   = Join-Path $root 'ipc'
$stateFile     = Join-Path $ipcDir 'state.txt'
$companionFile = Join-Path $ipcDir 'companion.txt'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
New-Item -ItemType Directory -Force $ipcDir | Out-Null

# Single instance: a second copy exits quietly.
$mutex = New-Object System.Threading.Mutex($false, 'PalBoomboxCompanion')
if (-not $mutex.WaitOne(0)) { exit }

function Get-Epoch { [int][double]::Parse((Get-Date -UFormat %s)) }

function Write-Heartbeat($pos) {
    $lines = @("alive=$(Get-Epoch)", "pos=$([math]::Round($pos,1))")
    Get-ChildItem $musicDir -File | Where-Object { $_.Extension -in '.wav', '.mp3', '.wma' } |
        Sort-Object Name | ForEach-Object { $lines += "track=$($_.Name)" }
    # UTF-8 without a BOM keeps custom filenames intact and remains easy for
    # Lua's line-based reader to parse.
    [IO.File]::WriteAllText($companionFile, ($lines -join "`n"), $utf8NoBom)
}

$player = New-Object System.Windows.Media.MediaPlayer
$currentTrack = ''
$lastHeartbeat = 0
$lastGameCheck = 0
$appliedSeekSeq = ''
$pendingSeek = -1
Write-Heartbeat 0

while ($true) {
    Start-Sleep -Milliseconds 100

    # Read state written by the Lua mod.
    $state = @{}
    $raw = if (Test-Path $stateFile) {
        [IO.File]::ReadAllText($stateFile, [Text.Encoding]::UTF8) -split "`r?`n"
    } else { @() }
    foreach ($line in $raw) {
        $kv = $line -split '=', 2
        if ($kv.Count -eq 2) { $state[$kv[0].Trim()] = $kv[1].Trim() }
    }

    if ($state['quit'] -eq '1') { break }

    $playing = $state['playing'] -eq '1'
    $track   = $state['track']

    if ($playing -and $track) {
        $trackPath = Join-Path $musicDir $track
        if (($track -ne $currentTrack) -and (Test-Path $trackPath)) {
            $player.Open([Uri]$trackPath)
            $player.Play()
            $currentTrack = $track
            $pendingSeek = -1  # re-arm seek for the new track
        }

        # Seek requests (multiplayer sync): applied once per seekseq, as soon
        # as the media duration is known.
        if ($state['seekseq'] -and $state['seekseq'] -ne $appliedSeekSeq) {
            $appliedSeekSeq = $state['seekseq']
            $s = 0.0
            if ([double]::TryParse($state['seek'], [ref]$s)) { $pendingSeek = $s } else { $pendingSeek = -1 }
        }
        if ($pendingSeek -ge 0 -and $player.NaturalDuration.HasTimeSpan) {
            $dur = $player.NaturalDuration.TimeSpan.TotalSeconds
            if ($dur -gt 1) {
                $player.Position = [TimeSpan]::FromSeconds($pendingSeek % $dur)
            }
            $pendingSeek = -1
        }
        $vol = 0.0; $bal = 0.0
        [void][double]::TryParse($state['volume'], [ref]$vol)
        [void][double]::TryParse($state['balance'], [ref]$bal)
        $player.Volume  = [math]::Max(0.0, [math]::Min(1.0, $vol))
        $player.Balance = [math]::Max(-1.0, [math]::Min(1.0, $bal))

        # Loop the track when it reaches the end.
        if ($player.NaturalDuration.HasTimeSpan) {
            $dur = $player.NaturalDuration.TimeSpan.TotalSeconds
            if ($dur -gt 0 -and $player.Position.TotalSeconds -ge $dur - 0.3) {
                $player.Position = [TimeSpan]::Zero
                $player.Play()
            }
        }
    }
    elseif ($currentTrack -ne '') {
        $player.Stop()
        $currentTrack = ''
    }

    $now = Get-Epoch
    if ($now - $lastHeartbeat -ge 2) {
        Write-Heartbeat $player.Position.TotalSeconds
        $lastHeartbeat = $now
    }

    # Exit when Palworld exits.
    if ($now - $lastGameCheck -ge 5) {
        $lastGameCheck = $now
        if (-not (Get-Process 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue)) { break }
    }
}

$player.Stop()
$player.Close()
Remove-Item $companionFile -ErrorAction SilentlyContinue
$mutex.ReleaseMutex()
