param([string]$FFmpeg = 'E:\Program Files\ffmpeg-7.1.1-essentials_build\bin\ffmpeg.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
foreach ($width in @(960,1280,1920)) {
    $frameDirectory = Join-Path $projectRoot "artifacts/movement-$width"
    $cue = Get-Content -Raw -LiteralPath (Join-Path $frameDirectory 'cues.json') | ConvertFrom-Json
    & $FFmpeg -hide_banner -loglevel error -y -framerate 15 -i (Join-Path $frameDirectory 'frame-%04d.jpg') -frames:v $cue.frames -c:v libx264 -preset medium -crf 19 -pix_fmt yuv420p -movflags +faststart (Join-Path $projectRoot "artifacts/movement-$width.mp4")
    if ($LASTEXITCODE -ne 0) { throw "Encoding failed for $width" }
    Write-Output "Encoded movement-$width.mp4 ($($cue.frames) frames)"
}
