param([ValidateSet('tanjiro','zenitsu')][string]$Character)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$artRoot=Join-Path $projectRoot 'output/imagegen/round-selected'
$jobs=Get-Content -Raw -LiteralPath (Join-Path $artRoot 'jobs.json') | ConvertFrom-Json
foreach ($job in $jobs) {
 if ($job.character -ne $Character) { continue }
 $recordPath=Join-Path $artRoot ('records/'+$job.id+'.json')
 if (Test-Path -LiteralPath $job.out) { Write-Output ('EXISTS '+$job.id);continue }
 if (Test-Path -LiteralPath $recordPath) { throw ('Inspect previous request before retrying: '+$job.id) }
 $record=[ordered]@{id=$job.id;status='requesting';model='gpt-image-2';quality='high';requested_size=$job.size;route='CPA via bundled image_gen.py';started_utc=[DateTime]::UtcNow.ToString('o');prompt=$job.prompt;output=$job.out;references=$job.references;cost=$null;accepted=$false}
 $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
 try {
  & 'output/codex-skills/cpa-imagegen/scripts/Invoke-CpaImage.ps1' -PromptFile $job.prompt -Out $job.out -Size $job.size -Model gpt-image-2 -Quality high -ReferenceImages @($job.references)
  $record.status='generated';$record.completed_utc=[DateTime]::UtcNow.ToString('o');$record.sha256=(Get-FileHash -LiteralPath $job.out -Algorithm SHA256).Hash.ToLower()
  $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
  Write-Output ('DONE '+$job.id)
 } catch {
  $record.status='uncertain';$record.error_type=$_.Exception.GetType().Name
  $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
  throw
 }
}