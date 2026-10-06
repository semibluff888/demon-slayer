"""Install the latest reviewed title poster from saved CPA sources. No network."""
from pathlib import Path
import json, hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
POSTERS=[
 ('title-ensemble-v3','title-all-hashira-r2'),
 ('title-ensemble-v3','title-all-hashira'),
 ('menu-settings-v1','title-ensemble-v2'),
]

def selected():
 for folder,identifier in POSTERS:
  out=ROOT/'output/imagegen'/folder
  source=out/'raw'/(identifier+'.png')
  record_path=out/'records'/(identifier+'.json')
  if not source.is_file() or not record_path.is_file():continue
  record=json.loads(record_path.read_text(encoding='utf-8-sig'))
  if record.get('status')=='generated' and record.get('accepted'):
   return out,source,record_path,record
 raise ValueError('No reviewed title poster is available.')

def ready():
 try:selected();return True
 except ValueError:return False

def build():
 out,source,record_path,record=selected()
 image=Image.open(source).convert('RGB')
 if abs(image.width/image.height-16/9)>.02:raise ValueError('Poster must keep its authored widescreen composition')
 actual_hash=hashlib.sha256(source.read_bytes()).hexdigest()
 if record.get('sha256')!=actual_hash:raise ValueError('Poster source changed after review')
 output=ROOT/'art/ui/title-poster.png'
 image.save(output)
 (out/'imports').mkdir(parents=True,exist_ok=True)
 (out/'imports/title-poster.json').write_text(json.dumps(dict(source=source.relative_to(ROOT).as_posix(),output=output.relative_to(ROOT).as_posix(),actual_size=list(image.size),sha256=actual_hash,crop=None,resampled=False),indent=2),encoding='utf-8')
 print('Installed reviewed title poster:',source.name,image.size)

if __name__=='__main__':build()
