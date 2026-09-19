param(
    [string[]]$Group = @('foundation'),
    [string[]]$Id = @(),
    [switch]$DryRun,
    [switch]$Probe
)
$ErrorActionPreference = 'Stop'
$productionRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $productionRoot
$jobs = Get-Content -Raw -LiteralPath 'output/imagegen/anime-v2/jobs.json' | ConvertFrom-Json
$helper = Join-Path $productionRoot 'output/codex-skills/cpa-imagegen/scripts/Invoke-CpaImage.ps1'
if ($Probe) { & $helper -Probe; return }
foreach ($job in $jobs) {
    if ($Id.Count -gt 0) { if ($job.id -notin $Id) { continue } }
    elseif ($job.group -notin $Group) { continue }
    $recordPath = Join-Path $productionRoot ('output/imagegen/anime-v2/records/' + $job.id + '.json')
    if (Test-Path -LiteralPath $job.out) { Write-Output ('EXISTS ' + $job.id); continue }
    if ((Test-Path -LiteralPath $recordPath) -and -not $DryRun) {
        $previous = Get-Content -Raw -LiteralPath $recordPath | ConvertFrom-Json
        if ($previous.status -in @('requesting', 'uncertain', 'failed')) {
            throw ('Inspect the prior request before retrying: ' + $job.id + ' (' + $previous.status + ')')
        }
    }
    $record = [ordered]@{id=$job.id; status='requesting'; model='gpt-image-2'; quality='high'; requested_size=$job.size;
        route='CPA via bundled image_gen.py'; started_utc=[DateTime]::UtcNow.ToString('o'); prompt=$job.prompt;
        output=$job.out; references=$job.references; price_verified=$false; cost=$null; accepted=$false}
    if (-not $DryRun) { $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8 }
    Write-Output ('GENERATING ' + $job.id + ' ' + $job.size)
    try {
        $invokeArgs = @{PromptFile=$job.prompt; Out=$job.out; Size=$job.size; Model='gpt-image-2'; Quality='high'}
        if ($job.references.Count -gt 0) { $invokeArgs.ReferenceImages = @($job.references) }
        if ($DryRun) { $invokeArgs.DryRun = $true }
        & $helper @invokeArgs
        if (-not $DryRun) {
            $record.status = 'generated'
            $record.completed_utc = [DateTime]::UtcNow.ToString('o')
            $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
        }
        Write-Output ('DONE ' + $job.id)
    } catch {
        if (-not $DryRun) {
            $record.status = 'uncertain'
            $record.error_type = $_.Exception.GetType().Name
            $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
        }
        throw
    }
}
