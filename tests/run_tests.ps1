param(
    [string]$Godot = $env:GODOT,
    [switch]$Capture
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$Godot = & (Join-Path $projectRoot 'tools/find-godot.ps1') -Godot $Godot
if (-not (Test-Path -LiteralPath $Godot)) {
    throw "Godot not found. Use -Godot 'path\to\Godot_console.exe'."
}
$artifactRoot = Join-Path $projectRoot 'artifacts'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null

function Invoke-DuelCheck {
    param([string[]]$EngineArgs, [string]$Expected)
    if ('--log-file' -notin $EngineArgs) {
        $scriptIndex = [Array]::IndexOf($EngineArgs, '--script')
        $checkName = [IO.Path]::GetFileNameWithoutExtension($EngineArgs[$scriptIndex + 1])
        if ('--capture' -in $EngineArgs) { $checkName += '-rendered' }
        $logArgs = @('--log-file', (Join-Path $artifactRoot ($checkName + '.log')))
        $userArgIndex = [Array]::IndexOf($EngineArgs, '--')
        if ($userArgIndex -ge 0) {
            $EngineArgs = @($EngineArgs[0..($userArgIndex - 1)]) + $logArgs + @($EngineArgs[$userArgIndex..($EngineArgs.Length - 1)])
        } else {
            $EngineArgs += $logArgs
        }
    }
    $lines = & $Godot @EngineArgs 2>&1
    $code = $LASTEXITCODE
    $outputText = ($lines | ForEach-Object { $_.ToString() }) -join "`n"
    Write-Host $outputText
    if ($code -ne 0 -or $outputText -match '(SCRIPT ERROR|ERROR:|FAIL:|instances were leaked|RIDs.*were leaked)' -or $outputText -notmatch $Expected) {
        throw "Godot check failed (exit $code): $($EngineArgs -join ' ')"
    }
    return $outputText
}

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/compile_check.gd') -Expected 'COMPILE / SCENE LOAD OK' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/release_combat_tests.gd') -Expected 'RELEASE COMBAT: 64 cases, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/input_tests.gd') -Expected 'INPUT TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/combat_tests.gd') -Expected 'COMBAT TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/damage_tests.gd') -Expected 'DAMAGE TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/awakening_tests.gd') -Expected 'AWAKENING TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/awakening_visual_tests.gd') -Expected 'AWAKENING VISUAL: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/awakening_presentation_tests.gd') -Expected 'AWAKENING PRESENTATION V2: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/movement_tests.gd') -Expected 'MOVEMENT TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/combo_practice_tests.gd') -Expected 'COMBO / PRACTICE TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/ui_tests.gd') -Expected 'UI TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/presentation_tests.gd') -Expected 'PRESENTATION TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/phase2_basics_tests.gd') -Expected 'PHASE TWO BASICS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/phase2_feedback_tests.gd') -Expected 'PHASE TWO FEEDBACK: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/battle_visual_tests.gd') -Expected 'BATTLE VISUAL TESTS: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/motion_fixes_tests.gd') -Expected 'MOTION FIXES: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/combat_polish_tests.gd') -Expected 'COMBAT POLISH TESTS: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/round_flow_tests.gd') -Expected 'ROUND FLOW TESTS: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/round_selected_tests.gd') -Expected 'ROUND SELECTED TESTS: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/round_polish_tests.gd') -Expected 'ROUND POLISH TESTS: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://demo/round-presentation/verify.gd') -Expected 'ROUND DEMO TESTS: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/roster_expansion_tests.gd') -Expected 'ROSTER EXPANSION: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/fate_revision_tests.gd') -Expected 'FATE REVISIONS: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/uppercut_polish_tests.gd') -Expected 'UPPERCUT POLISH: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/settings_tests.gd') -Expected 'SETTINGS TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/cinematic_tests.gd') -Expected 'CINEMATIC TESTS: \d+ passed, 0 failed' | Out-Null
Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/cinematic_handoff_tests.gd') -Expected 'CINEMATIC HANDOFF: \d+ passed, 0 failed' | Out-Null

Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--script', 'res://tests/cancel_assist_tests.gd') -Expected 'CANCEL ASSIST: \d+ passed, 0 failed' | Out-Null

$hashes = @()
foreach ($fps in @(30, 60, 144)) {
    $logPath = Join-Path $artifactRoot "fps-$fps.log"
    $result = Invoke-DuelCheck -EngineArgs @('--headless', '--path', $projectRoot, '--fixed-fps', "$fps", '--log-file', $logPath, '--script', 'res://tests/frame_rate_tests.gd') -Expected 'FRAME RATE RESULT: physics=1800'
    $hashes += [regex]::Match($result, 'hash=([a-f0-9]{64})').Groups[1].Value
}
if (($hashes | Select-Object -Unique).Count -ne 1 -or $hashes[0].Length -ne 64) {
    throw 'Combat state diverged across render frame rates.'
}
if ($Capture) {
    Invoke-DuelCheck -EngineArgs @('--path', $projectRoot, '--audio-driver', 'Dummy', '--script', 'res://tools/capture_awakening.gd') -Expected 'AWAKENING CAPTURE: \d+ checks, 0 failed' | Out-Null
    Invoke-DuelCheck -EngineArgs @('--path', $projectRoot, '--audio-driver', 'Dummy', '--script', 'res://tests/ui_tests.gd', '--', '--capture') -Expected 'UI TESTS: \d+ passed, 0 failed' | Out-Null
    Invoke-DuelCheck -EngineArgs @('--path', $projectRoot, '--audio-driver', 'Dummy', '--script', 'res://tests/presentation_tests.gd', '--', '--capture') -Expected 'PRESENTATION TESTS: \d+ passed, 0 failed' | Out-Null
    Invoke-DuelCheck -EngineArgs @('--path', $projectRoot, '--audio-driver', 'Dummy', '--script', 'res://tools/capture_phase2_matrix.gd') -Expected 'PHASE TWO MATRIX: \d+ screenshots, 0 failed' | Out-Null
}
$artPython = Join-Path $projectRoot '.venv/Scripts/python.exe'
if (Test-Path -LiteralPath $artPython) {
    & $artPython (Join-Path $projectRoot 'tests/art_pipeline_tests.py')
    if ($LASTEXITCODE -ne 0) { throw 'Artwork validation failed.' }
    & $artPython (Join-Path $projectRoot 'tests/roster_art_tests.py')
    if ($LASTEXITCODE -ne 0) { throw 'Expansion artwork validation failed.' }
    & $artPython (Join-Path $projectRoot 'tests/uppercut_art_tests.py')
    if ($LASTEXITCODE -ne 0) { throw 'Uppercut artwork validation failed.' }
    & $artPython (Join-Path $projectRoot 'tests/awakening_art_tests.py')
    if ($LASTEXITCODE -ne 0) { throw 'Awakening artwork validation failed.' }
    & $artPython (Join-Path $projectRoot 'tests/guard_fist_art_tests.py')
    if ($LASTEXITCODE -ne 0) { throw 'Guard fist artwork validation failed.' }
    & $artPython (Join-Path $projectRoot 'tests/motion_art_tests.py')
    if ($LASTEXITCODE -ne 0) { throw 'Motion artwork validation failed.' }
    & $artPython (Join-Path $projectRoot 'tests/fate_art_tests.py')
    if ($LASTEXITCODE -ne 0) { throw 'Fate artwork validation failed.' }
}
Write-Host 'All checks passed. Combat state is identical at 30 / 60 / 144 FPS.'
