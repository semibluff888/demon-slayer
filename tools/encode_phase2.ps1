param([string]$Batch = 'basics', [string]$FFmpeg = 'E:\Program Files\ffmpeg-7.1.1-essentials_build\bin\ffmpeg.exe')
$ErrorActionPreference = 'Stop'
$phaseRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/phase2'
$phaseFrames = Join-Path $phaseRoot $Batch
$phaseCue = Get-Content -Raw -LiteralPath (Join-Path $phaseFrames 'cues.json') | ConvertFrom-Json
& $FFmpeg -hide_banner -loglevel error -y -framerate 30 -i (Join-Path $phaseFrames 'frame-%05d.jpg') -i (Join-Path $phaseFrames 'soundtrack.wav') -frames:v $phaseCue.frames -c:v libx264 -preset medium -crf 19 -pix_fmt yuv420p -c:a aac -b:a 128k -shortest -movflags +faststart (Join-Path $phaseRoot ($Batch + '.mp4'))
if ($LASTEXITCODE -ne 0) { throw 'Phase two encoding failed' }
