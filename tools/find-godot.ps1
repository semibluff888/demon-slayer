param([string]$Godot = $env:GODOT)
$ErrorActionPreference = 'Stop'
if ($Godot) {
    if (Test-Path -LiteralPath $Godot -PathType Leaf) { return (Resolve-Path -LiteralPath $Godot).Path }
    $command = Get-Command $Godot -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    throw "Godot not found: $Godot"
}
foreach ($name in @('godot', 'godot4', 'Godot_v4.7.1-stable_win64_console.exe')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
}
$bundled = Join-Path (Split-Path -Parent $PSScriptRoot) 'build/engine/Godot_v4.7.1-stable_win64_console.exe'
if (Test-Path -LiteralPath $bundled) { return $bundled }
$local = Join-Path (Split-Path -Parent $PSScriptRoot) '.godot/engine-path.txt'
if (Test-Path -LiteralPath $local) {
    $saved = (Get-Content -LiteralPath $local -Raw).Trim()
    if (Test-Path -LiteralPath $saved -PathType Leaf) { return $saved }
}
throw 'Set GODOT to your Godot executable, or run tools/install-export-tools.ps1.'
