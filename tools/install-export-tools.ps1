param([switch]$SkipEditor)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = '4.7.1-stable'
$base = "https://github.com/godotengine/godot-builds/releases/download/$version"
$downloads = Join-Path $root 'build/downloads'
New-Item -ItemType Directory -Path $downloads -Force | Out-Null
Set-Content (Join-Path $root 'build/.gdignore') ''
$sums = Invoke-RestMethod "$base/SHA512-SUMS.txt"
function Get-VerifiedArchive([string]$name) {
    $path = Join-Path $downloads $name
    if (-not (Test-Path -LiteralPath $path)) { Invoke-WebRequest "$base/$name" -OutFile $path }
    $line = ($sums -split "`n" | Where-Object { $_.Trim().EndsWith($name) })
    if (@($line).Count -ne 1) { throw "Missing official checksum: $name" }
    $expected = ($line.Trim() -split '\s+')[0]
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA512).Hash -ine $expected) { throw "Checksum mismatch; remove and download again: $path" }
    return $path
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$template = Join-Path $root 'build/templates/windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $template)) {
    $archive = Get-VerifiedArchive "Godot_v${version}_export_templates.tpz"
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entry = $zip.GetEntry('templates/windows_release_x86_64.exe')
        if (-not $entry) { throw 'Windows x64 release template missing from official archive.' }
        New-Item -ItemType Directory -Path (Split-Path $template) -Force | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $template, $true)
    } finally { $zip.Dispose() }
    Remove-Item -LiteralPath $archive
}
if (-not $SkipEditor) {
    $engine = Join-Path $root "build/engine/Godot_v${version}_win64_console.exe"
    if (-not (Test-Path -LiteralPath $engine)) {
        $archive = Get-VerifiedArchive "Godot_v${version}_win64.exe.zip"
        [IO.Compression.ZipFile]::ExtractToDirectory($archive, (Join-Path $root 'build/engine'))
        Remove-Item -LiteralPath $archive
    }
}
Write-Host 'Godot 4.7.1 export tools are ready in build/.'
