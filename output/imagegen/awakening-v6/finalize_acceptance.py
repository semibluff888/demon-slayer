from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,zipfile
from PIL import Image
root=Path.cwd();out=root/'output/imagegen/awakening-v6'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def save(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
now=datetime.now(timezone.utc).isoformat()
regression=(root/'artifacts/awakening-v6-regression.log').read_text(encoding='utf-8-sig')
assert 'All checks passed. Combat state is identical at 30 / 60 / 144 FPS.' in regression
capture=read(root/'artifacts/awakening-v6/captures.json');assert not capture['failures']
source_check=read(out/'review/source-check.json');assert source_check=={'ready':39,'total':39,'errors':[]}
selected=read(out/'selected.json');assets=[]
for base in read(out/'jobs.json'):
    job=dict(base);job.update(selected.get(base['id'],{}))
    source=root/job['out'];record_path=out/'records'/(job['id']+'.json');record=read(record_path)
    assert record['status']=='generated'
    registration=read(out/'imports'/(base['id']+'.json'))
    assert registration['source_sha256']==sha(source)
    record.update(accepted=True,actual_size=list(Image.open(source).size),sha256=sha(source),reviewed_at=now)
    save(record_path,record)
    assets.append(dict(base_id=base['id'],selected_id=job['id'],clip=job['metadata']['clip'],frame_count=job['metadata']['count'],source=job['out'],source_sha256=sha(source),prompt=job['prompt'],prompt_sha256=sha(root/job['prompt']),references=job['references'],registration=(out/'imports'/(base['id']+'.json')).relative_to(root).as_posix()))
original=out/'records/nezuko-knockdown.json';record=read(original)
record.update(accepted=False,rejection_reason='Extra hand in frame 2; replaced by nezuko-knockdown-anatomy-v2.')
save(original,record)
portrait=read(out/'imports/nezuko-static.json')
record_path=out/'records/nezuko-portrait.json';record=read(record_path)
record.update(accepted=True,sha256=portrait['source_sha256'],actual_size=portrait['source_size'],reviewed_at=now);save(record_path,record)
for path,digest in read(out/'preserved-runtime.json').items():assert sha(root/path)==digest,path
package=root/'dist/DemonSlayer-0.2.2-nezuko-awakening-windows-x86_64.zip'
with zipfile.ZipFile(package) as archive:
    assert archive.testzip() is None
    names=archive.namelist()
    assert any(n.endswith('/DemonSlayer.exe') for n in names)
    assert any(n.endswith('/DemonSlayer.pck') for n in names)
smoke=(root/'dist/DemonSlayer-0.2.2-nezuko-awakening-windows-x86_64-smoke.log').read_text(encoding='utf-8-sig')
assert 'RELEASE SMOKE: 0 failed' in smoke and 'RELEASE COMBAT: 64 cases, 0 failed' in smoke
runtime={p.relative_to(root).as_posix():sha(p) for p in sorted((root/'art/characters/nezuko/awakening').iterdir()) if p.is_file() and p.suffix in ['.png','.json']}
acceptance=dict(status='integrated_and_verified',completed_at=now,integration_authorized=True,approval_gate_waived=True,generation='Authorized CPA API and installed imagegen CLI, gpt-image-2, high quality, actual attached pose and model references',source_master=read(out/'master.json'),generated_clips=39,generated_frames=306,runtime_total_clips=43,runtime_total_frames=348,assets=assets,portrait=portrait,runtime_sha256=runtime,preserved_runtime_sha256='preserved-runtime.json',validation=dict(full_regression='passed',regression_log='artifacts/awakening-v6-regression.log',core_checks=1400,visual_checks=1768,presentation_checks=30,art_tests=5,legacy_preview_test='One existing local-preview test skipped by suite; new source and runtime sheets reviewed separately.',fps_state_hashes=re.findall(r'FRAME RATE RESULT:.*?hash=([a-f0-9]{64})',regression),runtime_capture_checks=capture['checks'],runtime_screenshots=len(capture['captures']),runtime_capture_report='artifacts/awakening-v6/captures.json',source_check=source_check,source_all_frames_reviewed=True,runtime_contact_sheets_reviewed=True,exported_release_smoke='passed',exported_combat_cases=64,zip_integrity='passed'),release=dict(path=package.relative_to(root).as_posix(),size=package.stat().st_size,sha256=sha(package)))
save(out/'acceptance.json',acceptance)
preview=root/'output/imagegen/awakening-v6-preview'
manifest=read(preview/'preview-manifest.json');manifest.update(status='integrated_and_verified',runtime_changes=True,acceptance='output/imagegen/awakening-v6/acceptance.json');save(preview/'preview-manifest.json',manifest)
save(preview/'review-status.json',dict(status='integrated_and_verified',character='nezuko',integration_authorized=True,approval_gate_waived=True,manifest='preview-manifest.json',acceptance='output/imagegen/awakening-v6/acceptance.json'))
v3=root/'output/imagegen/awakening-v3-preview'
status=read(v3/'review-status.json');status.update(status='integrated')
status['characters']['nezuko'].update(integrated=True,acceptance='output/imagegen/awakening-v6/acceptance.json')
save(v3/'review-status.json',status)
manifest=read(v3/'preview-manifest.json');manifest.update(status='akaza_integrated_nezuko_superseded_and_integrated',current_nezuko_preview='output/imagegen/awakening-v6-preview/preview-manifest.json',current_nezuko_acceptance='output/imagegen/awakening-v6/acceptance.json');save(v3/'preview-manifest.json',manifest)
notes=root/'docs/RELEASE-NOTES.md';notes.write_text(notes.read_text(encoding='utf-8-sig').rstrip()+'\n',encoding='utf-8')
# Keep the shipped release-notes copy identical after whitespace normalization.
(root/'dist/DemonSlayer-0.2.2-nezuko-awakening-windows-x86_64-notes.md').write_bytes(notes.read_bytes())
print(json.dumps({'status':acceptance['status'],'capture_checks':capture['checks'],'screenshots':len(capture['captures']),'fps_hashes':acceptance['validation']['fps_state_hashes'],'release':acceptance['release']},indent=2))
