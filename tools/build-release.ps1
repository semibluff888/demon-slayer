param([string]$Godot = $env:GODOT, [string]$Version = '0.1.0')
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$') { throw 'Use a semantic version, for example 0.1.0.' }
$root = Split-Path -Parent $PSScriptRoot
$engine = & (Join-Path $PSScriptRoot 'find-godot.ps1') -Godot $Godot
$engineVersion = (& $engine --version | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $engineVersion -notlike '4.7.1.stable*') { throw "Expected Godot 4.7.1 stable, found: $engineVersion" }
$template = Join-Path $root 'build/templates/windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $template)) { throw 'Run tools/install-export-tools.ps1 first.' }
$build = Join-Path $root ('build/release-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $build 'project'
$packageName = "DemonSlayer-$Version-windows-x86_64"
$package = Join-Path $build $packageName
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $stage,$package,$dist -Force | Out-Null
Set-Content (Join-Path $root 'build/.gdignore') ''
Set-Content (Join-Path $dist '.gdignore') ''
# An allowlist prevents production sources, credentials, captures and tools entering the PCK.
foreach ($dir in @('art','moves','resources','scenes','scripts')) { Copy-Item -LiteralPath (Join-Path $root $dir) -Destination $stage -Recurse }
Copy-Item -LiteralPath (Join-Path $root 'project.godot') -Destination $stage
$preset = (Get-Content (Join-Path $root 'export_presets.cfg') -Raw).Replace('build/templates/windows_release_x86_64.exe', $template.Replace('\','/'))
Set-Content (Join-Path $stage 'export_presets.cfg') $preset -Encoding utf8
function Invoke-Engine([string[]]$Arguments, [string]$Name, [string]$Expected = '') {
    $log = Join-Path $build ($Name + '.log')
    & $engine @Arguments *> $log
    if ($LASTEXITCODE -ne 0) { Get-Content $log -Tail 40; throw "$Name failed; see $log" }
    $text = Get-Content $log -Raw
    if ($text -match '(SCRIPT ERROR|ERROR:|FAIL:)' -or ($Expected -and $text -notmatch $Expected)) { Get-Content $log -Tail 40; throw "$Name failed; see $log" }
}
# Capture source move properties before export; the packaged verifier compares every field.
Invoke-Engine @('--headless','--path',$root,'--script','res://tools/write_combat_manifest.gd','--',(Join-Path $stage 'resources/combat-manifest.json')) 'combat-manifest' 'COMBAT MANIFEST OK'
Invoke-Engine @('--headless','--path',$stage,'--editor','--import') 'import'
$exe = Join-Path $package 'DemonSlayer.exe'
Invoke-Engine @('--headless','--path',$stage,'--export-release','Windows Desktop',$exe) 'export'
$pck = Join-Path $package 'DemonSlayer.pck'
if (-not (Test-Path $exe) -or -not (Test-Path $pck)) { throw 'Export did not produce executable and PCK.' }
# The exported runtime itself must load every roster entry and its JSON-backed art.
$smokeLog = Join-Path $build 'runtime-smoke.log'
# Release templates disable path/script overrides; use the packaged application's own verifier.
$smokeError = Join-Path $build 'runtime-stderr.log'
$process = Start-Process -FilePath $exe -ArgumentList @('--headless','--','--verify-release') -WorkingDirectory $package -WindowStyle Hidden -PassThru -RedirectStandardOutput $smokeLog -RedirectStandardError $smokeError
if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Exported runtime check timed out.' }
$process.WaitForExit()
$smokeText = (Get-Content $smokeLog -Raw) + (Get-Content $smokeError -Raw)
if ($process.ExitCode -ne 0) { throw "Exported runtime failed: $smokeText" }
if ($smokeText -match '(SCRIPT ERROR|ERROR:|FAIL:)' -or $smokeText -notmatch 'RELEASE SMOKE: 0 failed' -or $smokeText -notmatch 'RELEASE COMBAT: 64 cases, 0 failed') { throw "Exported runtime smoke failed: $smokeText" }
Copy-Item (Join-Path $root 'docs/PLAYER-README.txt') (Join-Path $package 'README.txt')
Copy-Item (Join-Path $root 'THIRD-PARTY-NOTICES.md') $package
$licenses = Join-Path $package 'licenses'
New-Item -ItemType Directory -Path $licenses | Out-Null
Copy-Item (Join-Path $root 'art/fonts/*OFL.txt') $licenses
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $dist "$packageName.zip"
if (Test-Path $zip) { throw "Archive already exists; choose another version or move it: $zip" }
[IO.Compression.ZipFile]::CreateFromDirectory($package, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $packageName.zip" | Set-Content (Join-Path $dist "$packageName.sha256") -Encoding ascii
Copy-Item (Join-Path $root 'docs/RELEASE-NOTES.md') (Join-Path $dist "$packageName-notes.md")
# Staging copies and regenerated imports are disposable after verification.
$resolved = [IO.Path]::GetFullPath($build)
$boundary = [IO.Path]::GetFullPath((Join-Path $root 'build')) + [IO.Path]::DirectorySeparatorChar
if (-not $resolved.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging cleanup path.' }
Copy-Item $smokeLog (Join-Path $dist "$packageName-smoke.log")
Remove-Item -LiteralPath $resolved -Recurse -Force
Write-Host "Release ready: $zip"
Write-Host "SHA256: $hash"
