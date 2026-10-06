param([string]$Godot = $env:GODOT)
$ErrorActionPreference = 'Stop'
$engine = & (Join-Path $PSScriptRoot 'find-godot.ps1') -Godot $Godot
& $engine --path (Split-Path -Parent $PSScriptRoot)
exit $LASTEXITCODE
