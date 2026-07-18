# PalBoombox audio companion.
# Plays the boombox track with volume + stereo balance driven by the PalBoombox
# UE4SS Lua mod, which writes ..\ipc\state.txt ~10x/second based on where the
# player is relative to the placed boombox. Pure PowerShell + WPF MediaPlayer;
# no dependencies. Started automatically by the mod (or run it manually).
#
# Protocol (key=value lines):
#   state.txt  (mod -> companion): playing=0|1, track=<file>, volume=0..1,
#              balance=-1..1, quit=1
#   companion.txt (companion -> mod): alive=<unix time>, pos=<seconds>,
#              track=<file> (one line per available track in ..\music)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationCore

$root     = Split-Path $PSScriptRoot -Parent
$musicDir = Join-Path $root 'music'
$ipcDir   = Join-Path $root 'ipc'
$stateFile     = Join-Path $ipcDir 'state.txt'
$companionFile = Join-Path $ipcDir 'companion.txt'
New-Item -ItemType Directory -Force $ipcDir | Out-Null

# Single instance: a second copy exits quietly.
$mutex = New-Object System.Threading.Mutex($false, 'PalBoomboxCompanion')
if (-not $mutex.WaitOne(0)) { exit }

function Get-Epoch { [int][double]::Parse((Get-Date -UFormat %s)) }

function Write-Heartbeat($pos) {
    $lines = @("alive=$(Get-Epoch)", "pos=$([math]::Round($pos,1))")
    Get-ChildItem $musicDir -File | Where-Object { $_.Extension -in '.wav', '.mp3', '.wma' } |
        Sort-Object Name | ForEach-Object { $lines += "track=$($_.Name)" }
    Set-Content -Path $companionFile -Value ($lines -join "`n") -Encoding ascii
}

$player = New-Object System.Windows.Media.MediaPlayer
$currentTrack = ''
$lastHeartbeat = 0
$lastGameCheck = 0
Write-Heartbeat 0

while ($true) {
    Start-Sleep -Milliseconds 100

    # Read state written by the Lua mod.
    $state = @{}
    $raw = Get-Content $stateFile -ErrorAction SilentlyContinue
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
