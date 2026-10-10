param([switch]$Apply, [ValidateRange(1, 100)][int]$KeepReleaseArchives = 1)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
function Assert-LocalPath([string]$path) {
    $full = [IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Outside project: $full" }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked path: $full" }
    $parent = if ($item.PSIsContainer) { $item } else { $item.Directory }
    for ($cursor = $parent; $null -ne $cursor -and $cursor.FullName -ne $root; $cursor = $cursor.Parent) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked path: $full" }
    }
    return $full
}
$targets = @('artifacts', 'tmp', 'output/pip-cache', 'output/font-sources',
    'output/imagegen/anime-v2/review', 'output/imagegen/roster-v1/review',
    'output/imagegen/round-selected/review', 'output/imagegen/round-selected/packed',
    'demo/round-presentation/previews/frames', 'demo/round-presentation/previews/audio')
# Comparison sheets are derived from retained raw sources and registrations.
$imagegen = Join-Path $root 'output/imagegen'
if (Test-Path -LiteralPath $imagegen) {
    Get-ChildItem -LiteralPath $imagegen -Directory | ForEach-Object {
        $targets += 'output/imagegen/' + $_.Name + '/review'
    }
}
# The selected, licensed offline upscaler lives in runtime/. These are duplicate
# extracted distributions and downloads, not the runtime used by build tools.
$targets += @('output/super-resolution/models', 'output/super-resolution/realesrgan-ncnn-vulkan-v0.2.0-windows')
$files = [Collections.Generic.List[IO.FileInfo]]::new()
foreach ($relative in $targets) {
    $path = Join-Path $root $relative
    if (Test-Path -LiteralPath $path) {
        $path = Assert-LocalPath $path
        Get-ChildItem -LiteralPath $path -Recurse -File -Force | Where-Object Name -NE '.gdignore' | ForEach-Object { $files.Add($_) }
    }
}
$downloadRoot = Join-Path $root 'output/super-resolution'
if (Test-Path -LiteralPath $downloadRoot) {
    Get-ChildItem -LiteralPath $downloadRoot -File | Where-Object {
        $_.Name -like 'realesrgan-ncnn-vulkan-*-windows.zip' -or
        $_.Name -in @('input.jpg', 'input2.jpg', 'onepiece_demo.mp4', 'README_windows.md',
            'realesrgan-ncnn-vulkan.exe', 'vcomp140.dll', 'vcomp140d.dll')
    } | ForEach-Object { $files.Add($_) }
}
# Keep the newest release archive(s) by version, plus all release notes and hashes.
$releaseRoot = Join-Path $root 'dist'
$releases = @()
if (Test-Path -LiteralPath $releaseRoot) {
    $releases = @(Get-ChildItem -LiteralPath $releaseRoot -Filter 'DemonSlayer-*.zip' -File |
        Where-Object { $_.Name -match '^DemonSlayer-(\d+\.\d+\.\d+)(?:-|\.)' } |
        Sort-Object @{ Expression = { [version]([regex]::Match($_.Name, '^DemonSlayer-(\d+\.\d+\.\d+)').Groups[1].Value) }; Descending = $true }, @{ Expression = 'LastWriteTimeUtc'; Descending = $true })
    $releases | Select-Object -Skip $KeepReleaseArchives | ForEach-Object { $files.Add($_) }
    # Remove replaced ZIPs while retaining their hashes, notes and logs.
    Get-ChildItem -LiteralPath $releaseRoot -Directory -Filter 'superseded-*' | ForEach-Object {
        $backup = Assert-LocalPath $_.FullName
        Get-ChildItem -LiteralPath $backup -File -Filter 'DemonSlayer-*.zip' | ForEach-Object { $files.Add($_) }
    }
}
# Keep every imported resource still referenced by the game or historical demo.
$keep = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($relative in @('art', 'demo')) {
    Get-ChildItem -LiteralPath (Join-Path $root $relative) -Filter '*.import' -Recurse -File | ForEach-Object {
        foreach ($match in [regex]::Matches((Get-Content -LiteralPath $_.FullName -Raw), 'res://\.godot/imported/([^"\r\n]+)')) {
            $name = $match.Groups[1].Value
            $null = $keep.Add($name)
            $null = $keep.Add([IO.Path]::ChangeExtension($name, '.md5'))
        }
    }
}
$imported = Join-Path $root '.godot/imported'
if (Test-Path -LiteralPath $imported) {
    Get-ChildItem -LiteralPath $imported -File | Where-Object { -not $keep.Contains($_.Name) } | ForEach-Object { $files.Add($_) }
}
# Never delete version-controlled files, even if a generated folder changes later.
$tracked = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
& git -C $root -c core.quotepath=false ls-files | ForEach-Object { $null = $tracked.Add([IO.Path]::GetFullPath((Join-Path $root $_))) }
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect tracked files; aborting cleanup.' }
$total = 0L; $count = 0; $groups = @{}
foreach ($file in ($files | Sort-Object FullName -Unique)) {
    if ($tracked.Contains($file.FullName)) { continue }
    $path = Assert-LocalPath $file.FullName
    $total += $file.Length; $count++
    $relative = $path.Substring($root.Length + 1).Replace('\', '/')
    $category = $relative.Split('/')[0]
    if (-not $groups.ContainsKey($category)) { $groups[$category] = @{ Files = 0; Bytes = 0L } }
    $groups[$category].Files++; $groups[$category].Bytes += $file.Length
    if ($Apply) { Remove-Item -LiteralPath $path -Force }
}
if ($Apply) {
    foreach ($relative in $targets) {
        $directory = Join-Path $root $relative
        if (-not (Test-Path -LiteralPath $directory)) { continue }
        Get-ChildItem -LiteralPath $directory -Directory -Recurse -Force |
            Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
                $path = Assert-LocalPath $_.FullName
                if (-not (Get-ChildItem -LiteralPath $path -Force | Select-Object -First 1)) { Remove-Item -LiteralPath $path }
            }
    }
}
[pscustomobject]@{
    Applied = [bool]$Apply; Files = $count; Bytes = $total; FreedGiB = [math]::Round($total / 1GB, 3)
    KeptReleaseArchives = @($releases | Select-Object -First $KeepReleaseArchives -ExpandProperty Name)
    Categories = $groups
}
