param([string[]]$Id=@(),[string]$Kind='')
$ErrorActionPreference='Stop'
$battleRoot=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $battleRoot
$battleJobs=Get-Content -Raw 'output/imagegen/battle-v5/jobs.json' | ConvertFrom-Json
foreach($battleJob in $battleJobs) {
    if($Id.Count -gt 0 -and $battleJob.id -notin $Id){continue}
    if($Kind -and $battleJob.metadata.kind -ne $Kind){continue}
    $recordPath=Join-Path $battleRoot ('output/imagegen/battle-v5/records/'+$battleJob.id+'.json')
    if(Test-Path -LiteralPath $battleJob.out){Write-Output ('EXISTS '+$battleJob.id);continue}
    if(Test-Path -LiteralPath $recordPath){throw ('Inspect previous request before retry: '+$battleJob.id)}
    $record=[ordered]@{id=$battleJob.id;status='requesting';model='gpt-image-2';quality='high';requested_size=$battleJob.size;route='CPA via bundled image_gen.py';started_utc=[DateTime]::UtcNow.ToString('o');prompt=$battleJob.prompt;output=$battleJob.out;references=$battleJob.references;cost=$null;accepted=$false}
    $record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $recordPath -Encoding utf8
    Write-Output ('GENERATING '+$battleJob.id)
    try {
        & '.\output\codex-skills\cpa-imagegen\scripts\Invoke-CpaImage.ps1' -PromptFile $battleJob.prompt -Out $battleJob.out -Size $battleJob.size -Quality high -ReferenceImages @($battleJob.references)
        if(-not(Test-Path -LiteralPath $battleJob.out)){throw 'Generation returned without an image'}
        $record.status='generated'
        $record.completed_utc=[DateTime]::UtcNow.ToString('o')
        $record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $recordPath -Encoding utf8
        & '.\.venv\Scripts\python.exe' -c 'import sys,json,hashlib;from PIL import Image;from pathlib import Path;p=Path(sys.argv[1]);d=json.loads(p.read_text(encoding="utf-8-sig"));im=Path(d["output"]);d["actual_size"]=list(Image.open(im).size);d["sha256"]=hashlib.sha256(im.read_bytes()).hexdigest();p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n",encoding="utf-8");print("ACTUAL",d["actual_size"])' $recordPath
    } catch {
        $record.status='uncertain'
        $record.error_type=$_.Exception.GetType().Name
        $record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $recordPath -Encoding utf8
        throw
    }
}

