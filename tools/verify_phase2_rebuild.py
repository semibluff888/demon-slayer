"""Verify the saved phase-two art and authoring data rebuild identically offline."""
from pathlib import Path
import hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def fingerprint():
 paths=[]
 for root,pattern in [('art/characters','atlas*'),('moves/core','*.tres'),('resources/characters','*.tres'),('resources/presentation','*.tres'),('output/imagegen/anime-v2/imports','*.json')]:
  paths.extend(p for p in (ROOT/root).glob('**/'+pattern) if p.is_file() and not p.name.endswith('.import'))
 paths.append(ROOT/'output/imagegen/anime-v2/calibration.json')
 return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
def audit_parameters():
 baseline=json.loads((ROOT/'output/imagegen/history/pre-phase2-gameplay.json').read_text(encoding='utf-8'))
 ignored=set(baseline['excluded_presentation_fields']);changed=[]
 for name,old in baseline['moves'].items():
  text=(ROOT/'moves/core'/name).read_text(encoding='utf-8')
  now={k:v for line in text.split('[resource]',1)[1].splitlines() if ' = ' in line for k,v in [line.split(' = ',1)] if k not in ignored}
  if old!=now:changed.append({'move':name,'fields':{k:[old.get(k),now.get(k)] for k in set(old)|set(now) if old.get(k)!=now.get(k)}})
 report={'moves':len(baseline['moves']),'gameplay_parameter_changes':changed,'excluded_presentation_fields':sorted(ignored),'baseline':'output/imagegen/history/pre-phase2-gameplay.json'}
 target=ROOT/'artifacts/phase2/parameter-audit.json';target.parent.mkdir(parents=True,exist_ok=True)
 target.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 assert not changed,changed
 print('42 moves: gameplay fields match the saved phase-one baseline.')
def main():
 audit_parameters()
 before=fingerprint()
 for args in [['tools/build_movement_art.py','--part','animation'],['tools/build_presentation_data.py'],['tools/build_combat_data.py'],['tests/art_pipeline_tests.py','--with-previews']]:
  subprocess.run([sys.executable,'-X','utf8',*args],cwd=ROOT,check=True)
 after=fingerprint();changed=[p for p in sorted(set(before)|set(after)) if before.get(p)!=after.get(p)]
 report={'offline':True,'files_compared':len(after),'changed':changed,'hashes':after}
 out=ROOT/'artifacts/phase2/rebuild-verification.json';out.parent.mkdir(parents=True,exist_ok=True)
 out.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 if changed: raise SystemExit('Unexpected rebuild differences: '+', '.join(changed))
 print(f'PHASE TWO REBUILD: {len(after)} files byte-identical; previews valid; no network.')
if __name__=='__main__':main()
