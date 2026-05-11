#Requires -Version 5.1
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'PowerControl.ico')
)

Add-Type -AssemblyName System.Drawing

function New-IconPng {
    param([int]$Size)

    $bitmap = New-Object Drawing.Bitmap $Size, $Size
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([Drawing.Color]::Transparent)

    $scale = $Size / 256.0
    function S([float]$value) { [int][Math]::Round($value * $scale) }

    $rect = New-Object Drawing.Rectangle (S 18), (S 18), (S 220), (S 220)
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $radius = S 52
    $diameter = $radius * 2
    $path.AddArc($rect.Left, $rect.Top, $diameter, $diameter, 180, 90)
    $path.AddArc($rect.Right - $diameter, $rect.Top, $diameter, $diameter, 270, 90)
    $path.AddArc($rect.Right - $diameter, $rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($rect.Left, $rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()

    $brush = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, ([Drawing.Color]::FromArgb(255, 16, 110, 145)), ([Drawing.Color]::FromArgb(255, 40, 180, 135)), 45
    $graphics.FillPath($brush, $path)

    $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 235, 255, 252)), (S 18)
    $pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawLine($pen, (S 128), (S 58), (S 128), (S 110))

    $arcPen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 235, 255, 252)), (S 18)
    $arcPen.StartCap = [Drawing.Drawing2D.LineCap]::Round
    $arcPen.EndCap = [Drawing.Drawing2D.LineCap]::Round
    $graphics.DrawArc($arcPen, (S 71), (S 82), (S 114), (S 114), 135, 270)

    $bolt = New-Object Drawing.Drawing2D.GraphicsPath
    $bolt.AddPolygon(@(
        (New-Object Drawing.Point (S 146), (S 120)),
        (New-Object Drawing.Point (S 111), (S 180)),
        (New-Object Drawing.Point (S 139), (S 180)),
        (New-Object Drawing.Point (S 120), (S 220)),
        (New-Object Drawing.Point (S 183), (S 151)),
        (New-Object Drawing.Point (S 151), (S 151))
    ))
    $graphics.FillPath((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 255, 213, 74))), $bolt)

    $stream = New-Object IO.MemoryStream
    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    return $stream.ToArray()
}

$sizes = @(16, 32, 48, 256)
$images = @()
foreach ($size in $sizes) {
    $images += ,@{
        Size = $size
        Bytes = New-IconPng -Size $size
    }
}

$fs = [IO.File]::Create($OutputPath)
$writer = New-Object IO.BinaryWriter $fs
try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$images.Count)

    $offset = 6 + (16 * $images.Count)
    foreach ($image in $images) {
        $sizeByte = if ($image.Size -eq 256) { 0 } else { $image.Size }
        $writer.Write([byte]$sizeByte)
        $writer.Write([byte]$sizeByte)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$image.Bytes.Length)
        $writer.Write([UInt32]$offset)
        $offset += $image.Bytes.Length
    }

    foreach ($image in $images) {
        $writer.Write([byte[]]$image.Bytes)
    }
}
finally {
    $writer.Dispose()
    $fs.Dispose()
}

Write-Host "Wrote $OutputPath"
