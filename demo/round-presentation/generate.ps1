param([ValidateSet('tanjiro','zenitsu')][string]$Character, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$demoRoot = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $demoRoot)
Set-Location -LiteralPath $projectRoot
$helper = Join-Path $projectRoot 'output/codex-skills/cpa-imagegen/scripts/Invoke-CpaImage.ps1'
$jobs = Get-Content -Raw -LiteralPath (Join-Path $demoRoot 'jobs.json') | ConvertFrom-Json
foreach ($job in $jobs) {
    if ($job.character -ne $Character) { continue }
    $recordPath = Join-Path $demoRoot ('records/' + $job.id + '.json')
    if (Test-Path -LiteralPath $job.out) { Write-Output ('EXISTS ' + $job.id); continue }
    if (Test-Path -LiteralPath $recordPath) { throw ('Inspect previous request before retrying: ' + $job.id) }
    $record = [ordered]@{id=$job.id;status='requesting';model='gpt-image-2';quality='high';requested_size=$job.size;route='CPA via bundled image_gen.py';started_utc=[DateTime]::UtcNow.ToString('o');prompt=$job.prompt;output=$job.out;references=$job.references;cost=$null;accepted=$false}
    if (-not $DryRun) { $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8 }
    Write-Output ('GENERATING ' + $job.id)
    try {
        $invokeArgs = @{PromptFile=$job.prompt;Out=$job.out;Size=$job.size;Model='gpt-image-2';Quality='high';ReferenceImages=@($job.references)}
        if ($DryRun) { $invokeArgs.DryRun = $true }
        & $helper @invokeArgs
        if (-not $DryRun) {
            $record.status='generated'
            $record.completed_utc=[DateTime]::UtcNow.ToString('o')
            $record.sha256=(Get-FileHash -LiteralPath $job.out -Algorithm SHA256).Hash.ToLower()
            $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
        }
        Write-Output ('DONE ' + $job.id)
    } catch {
        if (-not $DryRun) {
            $record.status='uncertain'
            $record.error_type=$_.Exception.GetType().Name
            $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
        }
        throw
    }
}
