"""Install the latest reviewed title poster from saved sources. No network."""
from pathlib import Path
import json, hashlib
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parents[1]
# Newest first. User-supplied art is listed in its folder's manifest.json;
# generated art keeps one review record per image under records/.
POSTERS=[
 ('user-assets/title-poster','nine-friends-sunrise'),
 ('imagegen/title-ensemble-v3','title-all-hashira-r2'),
 ('imagegen/title-ensemble-v3','title-all-hashira'),
 ('imagegen/menu-settings-v1','title-ensemble-v2'),
]

def review(out,identifier):
 manifest=out/'manifest.json'
 if manifest.is_file():
  for record in json.loads(manifest.read_text(encoding='utf-8-sig'))['records']:
   if record['key']==identifier and record.get('accepted'):
    return manifest,dict(record,status='supplied',sha256=record['source_sha256'],actual_size=record['source_size'])
  return None
 record_path=out/'records'/(identifier+'.json')
 if not record_path.is_file():return None
 record=json.loads(record_path.read_text(encoding='utf-8-sig'))
 return (record_path,record) if record.get('status')=='generated' and record.get('accepted') else None

def selected():
 for folder,identifier in POSTERS:
  out=ROOT/'output'/folder
  source=out/'raw'/(identifier+'.png')
  reviewed=review(out,identifier) if source.is_file() else None
  if reviewed:return out,source,reviewed[0],reviewed[1]
 raise ValueError('No reviewed title poster is available.')

def ready():
 try:selected();return True
 except ValueError:return False

def sha256(path):return hashlib.sha256(path.read_bytes()).hexdigest()

# Accepted neural upscale of a poster, saved as hd/<id>.json beside its raw/ source.
# The inference output is kept, so rebuilding never reruns the model.
def upscale(out,identifier):
 path=out/'hd'/(identifier+'.json')
 if not path.is_file():return None
 record=json.loads(path.read_text(encoding='utf-8-sig'))
 return record if record.get('accepted') else None

# Upscaled detail everywhere except the keep_original zones (source pixels), which
# keep the Lanczos-upscaled original under a feathered mask, then crop and resize.
def compose(source,record):
 original=Image.open(source).convert('RGB')
 detailed=Image.open(ROOT/record['output']).convert('RGB')
 mask=Image.new('L',original.size,0)
 for polygon in record['keep_original']:ImageDraw.Draw(mask).polygon([tuple(point) for point in polygon],fill=255)
 mask=mask.filter(ImageFilter.GaussianBlur(record['feather'])).resize(detailed.size,Image.BILINEAR)
 image=Image.composite(original.resize(detailed.size,Image.LANCZOS),detailed,mask)
 return image.crop(tuple(record['crop'])).resize(tuple(record['runtime_size']),Image.LANCZOS)

def build():
 out,source,record_path,record=selected()
 image=Image.open(source).convert('RGB')
 if abs(image.width/image.height-16/9)>.02:raise ValueError('Poster must keep its authored widescreen composition')
 actual_hash=sha256(source)
 if record.get('sha256')!=actual_hash:raise ValueError('Poster source changed after review')
 hd=upscale(out,source.stem)
 if hd:
  if hd['source_sha256']!=actual_hash or hd['sha256']!=sha256(ROOT/hd['output']):raise ValueError('Upscaled poster no longer matches its record')
  image=compose(source,hd)
 output=ROOT/'art/ui/title-poster.png'
 image.save(output)
 (out/'imports').mkdir(parents=True,exist_ok=True)
 (out/'imports/title-poster.json').write_text(json.dumps(dict(source=source.relative_to(ROOT).as_posix(),output=output.relative_to(ROOT).as_posix(),actual_size=list(image.size),sha256=actual_hash,
  processing=(out/'hd'/(source.stem+'.json')).relative_to(ROOT).as_posix() if hd else None,crop=hd['crop'] if hd else None,resampled=hd is not None),indent=2),encoding='utf-8')
 print('Installed reviewed title poster:',source.name,image.size)

if __name__=='__main__':build()
