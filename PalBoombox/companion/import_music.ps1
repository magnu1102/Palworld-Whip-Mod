param(
    [Parameter(Mandatory = $true)][string]$RequestId,
    [string[]]$SourceFiles
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path $PSScriptRoot -Parent
$musicDir = Join-Path $root 'music'
$ipcDir = Join-Path $root 'ipc'
$resultFile = Join-Path $ipcDir 'import_result.txt'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

New-Item -ItemType Directory -Force $musicDir, $ipcDir | Out-Null

function Write-ImportResult([string]$status, [int]$count, [string]$message) {
    $safeMessage = $message -replace '[\r\n]', ' '
    $lines = @(
        "request=$RequestId"
        "status=$status"
        "count=$count"
        "message=$safeMessage"
    )
    [IO.File]::WriteAllText($resultFile, ($lines -join "`n"), $utf8NoBom)
}

function Get-AvailableDestination([string]$sourcePath) {
    $name = [IO.Path]::GetFileName($sourcePath)
    $candidate = Join-Path $musicDir $name
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }

    # Selecting a file that is already in the music directory is harmless.
    if ([string]::Equals(
        [IO.Path]::GetFullPath($sourcePath),
        [IO.Path]::GetFullPath($candidate),
        [StringComparison]::OrdinalIgnoreCase)) {
        return $candidate
    }

    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    $extension = [IO.Path]::GetExtension($name)
    for ($suffix = 2; $suffix -lt 10000; $suffix++) {
        $candidate = Join-Path $musicDir ("{0} ({1}){2}" -f $stem, $suffix, $extension)
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw "Could not find a free filename for '$name'."
}

function Find-IdenticalTrack([string]$sourcePath) {
    $source = Get-Item -LiteralPath $sourcePath -ErrorAction Stop
    $sourceHash = $null
    foreach ($existing in (Get-ChildItem -LiteralPath $musicDir -File -ErrorAction SilentlyContinue)) {
        if ($existing.Length -ne $source.Length) { continue }
        if (-not $sourceHash) {
            $sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
        }
        $existingHash = (Get-FileHash -LiteralPath $existing.FullName -Algorithm SHA256).Hash
        if ([string]::Equals($sourceHash, $existingHash, [StringComparison]::OrdinalIgnoreCase)) {
            return $existing.FullName
        }
    }
    return $null
}

try {
    $selectedFiles = $SourceFiles
    if (-not $selectedFiles -or $selectedFiles.Count -eq 0) {
        [System.Windows.Forms.Application]::EnableVisualStyles()
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Add music to PalBoombox'
        $dialog.Filter = 'Supported audio (*.mp3;*.wav;*.wma)|*.mp3;*.wav;*.wma|MP3 files (*.mp3)|*.mp3|Wave files (*.wav)|*.wav|Windows Media Audio (*.wma)|*.wma'
        $dialog.Multiselect = $true
        $dialog.RestoreDirectory = $true
        $dialog.CheckFileExists = $true
        $dialog.InitialDirectory = [Environment]::GetFolderPath('MyMusic')

        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            Write-ImportResult 'cancelled' 0 'No files selected.'
            exit 0
        }
        $selectedFiles = $dialog.FileNames
    }

    $imported = New-Object System.Collections.Generic.List[string]
    $alreadyPresent = New-Object System.Collections.Generic.List[string]
    foreach ($sourcePath in $selectedFiles) {
        $extension = [IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
        if ($extension -notin '.mp3', '.wav', '.wma') { continue }

        $identical = Find-IdenticalTrack $sourcePath
        if ($identical) {
            $alreadyPresent.Add([IO.Path]::GetFileName($identical))
            continue
        }

        $destination = Get-AvailableDestination $sourcePath
        if (-not [string]::Equals(
            [IO.Path]::GetFullPath($sourcePath),
            [IO.Path]::GetFullPath($destination),
            [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $sourcePath -Destination $destination
        }
        $imported.Add([IO.Path]::GetFileName($destination))
    }

    if ($imported.Count -eq 0 -and $alreadyPresent.Count -gt 0) {
        Write-ImportResult 'unchanged' 0 ("Already present: " + ($alreadyPresent -join ', '))
        exit 0
    }

    if ($imported.Count -eq 0) {
        Write-ImportResult 'error' 0 'No supported audio files were selected.'
        exit 1
    }

    $message = $imported -join ', '
    if ($alreadyPresent.Count -gt 0) {
        $message += "; already present: " + ($alreadyPresent -join ', ')
    }
    Write-ImportResult 'imported' $imported.Count $message
} catch {
    Write-ImportResult 'error' 0 $_.Exception.Message
    exit 1
}
