# Generates the PalBoombox item icon (256x256 PNG with transparency).
# Output: PalBoomboxItem/resources/images/boombox.png
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$size = 256
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$body    = [System.Drawing.Color]::FromArgb(255,  52,  73,  94)
$bodyHi  = [System.Drawing.Color]::FromArgb(255,  84, 110, 134)
$grille  = [System.Drawing.Color]::FromArgb(255,  30,  42,  54)
$cone    = [System.Drawing.Color]::FromArgb(255,  70,  70,  70)
$teal    = [System.Drawing.Color]::FromArgb(255,  38, 198, 218)
$silver  = [System.Drawing.Color]::FromArgb(255, 189, 195, 199)

# Shadow
$shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, 0, 0, 0))
$g.FillEllipse($shadow, 30, 208, 196, 26)

# Handle
$handlePen = New-Object System.Drawing.Pen($silver, 12)
$g.DrawArc($handlePen, 66, 30, 124, 70, 180, 180)
$handlePen.Dispose()

# Body
$bodyBrush = New-Object System.Drawing.SolidBrush($body)
$g.FillRectangle($bodyBrush, 24, 76, 208, 140)
$hiBrush = New-Object System.Drawing.SolidBrush($bodyHi)
$g.FillRectangle($hiBrush, 24, 76, 208, 22)
$bodyBrush.Dispose(); $hiBrush.Dispose()

# Speakers
foreach ($cx in @(76, 180)) {
    $b = New-Object System.Drawing.SolidBrush($grille)
    $g.FillEllipse($b, $cx - 38, 116, 76, 76); $b.Dispose()
    $b = New-Object System.Drawing.SolidBrush($cone)
    $g.FillEllipse($b, $cx - 26, 128, 52, 52); $b.Dispose()
    $b = New-Object System.Drawing.SolidBrush($teal)
    $g.FillEllipse($b, $cx - 9, 145, 18, 18); $b.Dispose()
}

# Cassette deck
$deck = New-Object System.Drawing.SolidBrush($grille)
$g.FillRectangle($deck, 106, 122, 44, 30); $deck.Dispose()
$reel = New-Object System.Drawing.SolidBrush($silver)
$g.FillEllipse($reel, 111, 130, 13, 13)
$g.FillEllipse($reel, 132, 130, 13, 13); $reel.Dispose()

# Control knobs
$knob = New-Object System.Drawing.SolidBrush($teal)
$g.FillEllipse($knob, 112, 162, 12, 12)
$g.FillEllipse($knob, 132, 162, 12, 12); $knob.Dispose()

# Music notes
$notePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(235, 255, 255, 255), 5)
$noteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(235, 255, 255, 255))
$g.DrawLine($notePen, 224, 46, 224, 76); $g.FillEllipse($noteBrush, 214, 70, 14, 11)
$g.DrawLine($notePen, 246, 60, 246, 86); $g.FillEllipse($noteBrush, 236, 80, 14, 11)
$notePen.Dispose(); $noteBrush.Dispose()

$g.Dispose()
$outDir = Join-Path $PSScriptRoot '..\PalBoomboxItem\resources\images'
New-Item -ItemType Directory -Force $outDir | Out-Null
$out = Join-Path $outDir 'boombox.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Wrote $out"
