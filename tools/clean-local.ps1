param([switch]$Apply)
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
$files = [Collections.Generic.List[IO.FileInfo]]::new()
foreach ($relative in $targets) {
    $path = Join-Path $root $relative
    if (Test-Path -LiteralPath $path) {
        $path = Assert-LocalPath $path
        Get-ChildItem -LiteralPath $path -Recurse -File -Force | Where-Object Name -NE '.gdignore' | ForEach-Object { $files.Add($_) }
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
$total = 0L; $count = 0
foreach ($file in ($files | Sort-Object FullName -Unique)) {
    if ($tracked.Contains($file.FullName)) { continue }
    $path = Assert-LocalPath $file.FullName
    $total += $file.Length; $count++
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
[pscustomobject]@{ Applied = [bool]$Apply; Files = $count; FreedGiB = [math]::Round($total / 1GB, 3) }
