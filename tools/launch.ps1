param([string]$Godot = $env:GODOT)
$ErrorActionPreference = 'Stop'
try {
    $engine = & (Join-Path $PSScriptRoot 'find-godot.ps1') -Godot $Godot
    # Tests and exports use the console executable; local play uses its GUI sibling.
    if ($engine -match '_console\.exe$') {
        $guiEngine = $engine -replace '_console\.exe$', '.exe'
        if (-not (Test-Path -LiteralPath $guiEngine -PathType Leaf)) {
            throw "Godot GUI executable not found: $guiEngine"
        }
        $engine = $guiEngine
    }
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Start-Process -FilePath $engine -ArgumentList @('--path', ('"{0}"' -f $projectRoot)) -WorkingDirectory $projectRoot -WindowStyle Normal | Out-Null
    exit 0
} catch {
    # launch.cmd hides its console, so startup failures need a visible explanation.
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Game launch failed') | Out-Null
    exit 1
}
