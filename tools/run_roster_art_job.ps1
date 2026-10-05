param([Parameter(Mandatory=$true)][string]$Id)
$ErrorActionPreference = 'Stop'
$productionRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $productionRoot
$job = Get-Content -Raw -LiteralPath 'output/imagegen/roster-v1/jobs.json' | ConvertFrom-Json | Where-Object { $_.id -eq $Id }
if (-not $job) { throw 'Unknown artwork job' }
$recordPath = Join-Path $productionRoot ('output/imagegen/roster-v1/records/' + $Id + '.json')
if (Test-Path -LiteralPath $job.out) { Write-Output ('EXISTS ' + $Id); exit 0 }
if (Test-Path -LiteralPath $recordPath) { throw ('Inspect prior request before retry: ' + $Id) }
$record = [ordered]@{id=$Id;status='requesting';model='gpt-image-2';quality='high';requested_size=$job.size;route='CPA via installed image_gen.py';prompt=$job.prompt;output=$job.out;references=$job.references;started_utc=[DateTime]::UtcNow.ToString('o');cost=$null;accepted=$false}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
try {
    $invokeArgs = @{PromptFile=$job.prompt;Out=$job.out;Size=$job.size;Model='gpt-image-2';Quality='high'}
    if ($job.references.Count -gt 0) { $invokeArgs.ReferenceImages=@($job.references) }
    & (Join-Path $productionRoot 'output/codex-skills/cpa-imagegen/scripts/Invoke-CpaImage.ps1') @invokeArgs
    $record.status='generated'
    $record.completed_utc=[DateTime]::UtcNow.ToString('o')
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
} catch {
    $record.status='uncertain'
    $record.error_type=$_.Exception.GetType().Name
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
    throw
}
