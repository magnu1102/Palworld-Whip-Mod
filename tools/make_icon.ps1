# Generates the PalWhip item icon (256x256 PNG with transparency).
# Output: PalWhipItem/resources/images/whip.png
# Rerun after tweaking; the PNG is committed so users never need to run this.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$size = 256
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$leather     = [System.Drawing.Color]::FromArgb(255, 121,  72,  36)
$leatherDark = [System.Drawing.Color]::FromArgb(255,  84,  48,  22)
$leatherHi   = [System.Drawing.Color]::FromArgb(255, 168, 108,  58)
$handleCol   = [System.Drawing.Color]::FromArgb(255,  56,  34,  18)
$bandCol     = [System.Drawing.Color]::FromArgb(255, 205, 160,  60)

# Soft drop shadow under the coil
$shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, 0, 0, 0))
$g.FillEllipse($shadow, 48, 170, 160, 46)

# Coil: three concentric rings, darkest outside
foreach ($ring in @(
        @{ r = 72; w = 26; c = $leatherDark },
        @{ r = 52; w = 24; c = $leather },
        @{ r = 33; w = 22; c = $leatherHi })) {
    $pen = New-Object System.Drawing.Pen($ring.c, $ring.w)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $cx = 118; $cy = 140; $r = $ring.r
    $g.DrawEllipse($pen, $cx - $r, $cy - $r, 2 * $r, 2 * $r)
    $pen.Dispose()
}

# Lash: tapering curve rising from the coil to the top-right, ending in a crack tip
$lashPts = @(
    @{ p1 = (118, 68);  p2 = (150, 30);  p3 = (185, 22);  p4 = (208, 34);  w = 14 },
    @{ p1 = (208, 34);  p2 = (226, 44);  p3 = (234, 58);  p4 = (228, 74);  w = 9  },
    @{ p1 = (228, 74);  p2 = (222, 88);  p3 = (208, 92);  p4 = (196, 86);  w = 5  }
)
foreach ($seg in $lashPts) {
    $pen = New-Object System.Drawing.Pen($leather, $seg.w)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $g.DrawBezier($pen,
        $seg.p1[0], $seg.p1[1], $seg.p2[0], $seg.p2[1],
        $seg.p3[0], $seg.p3[1], $seg.p4[0], $seg.p4[1])
    $pen.Dispose()
}

# Crack spark at the lash tip
$spark = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 255, 232, 140), 4)
foreach ($line in @((188,78,176,66), (192,92,182,102), (200,74,196,60))) {
    $g.DrawLine($spark, $line[0], $line[1], $line[2], $line[3])
}
$spark.Dispose()

# Handle: rotated dark grip with gold bands, tucked into the coil's lower-left
$state = $g.Save()
$g.TranslateTransform(62, 196)
$g.RotateTransform(38)
$handleBrush = New-Object System.Drawing.SolidBrush($handleCol)
$g.FillRectangle($handleBrush, -10, -70, 22, 92)
$bandBrush = New-Object System.Drawing.SolidBrush($bandCol)
$g.FillRectangle($bandBrush, -10, -70, 22, 9)
$g.FillRectangle($bandBrush, -10, 10, 22, 9)
$handleBrush.Dispose(); $bandBrush.Dispose()
$g.Restore($state)

$g.Dispose()

$outDir = Join-Path $PSScriptRoot '..\PalWhipItem\resources\images'
New-Item -ItemType Directory -Force $outDir | Out-Null
$out = Join-Path $outDir 'whip.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Wrote $out"
