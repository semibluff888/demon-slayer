"""Assemble generated clip segments without resampling or normalizing silhouettes."""
import argparse,hashlib,json
from pathlib import Path
from PIL import Image
import numpy as np
from build_awakening_art import cyan_matte
from build_roster_art import components
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/awakening-v7'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 global OUT
 p=argparse.ArgumentParser();p.add_argument('--partial',action='store_true');p.add_argument('--source-dir',default='output/imagegen/awakening-v7');args=p.parse_args();OUT=ROOT/args.source_dir
 for job in read(OUT/'jobs.json'):
  sources=job.get('source_sheets',[])
  if not sources:continue
  if not all((ROOT/s['out']).exists() for s in sources):
   if args.partial:continue
   raise ValueError('Missing segments for '+job['id'])
  records=[read(OUT/'records'/(s['id']+'.json')) for s in sources]
  if not all(r['status']=='generated' for r in records):raise ValueError('Uncertain request')
  images=[Image.open(ROOT/s['out']).convert('RGBA') for s in sources]
  # Requests can return different native widths. Pad only: no resampling and no
  # assumption that cell size is a physical anatomy ruler.
  width=max(im.width for im in images)
  combined=Image.new('RGBA',(width,sum(im.height for im in images)))
  y=0;provenance=[]
  for src,im in zip(sources,images):
   x=(width-im.width)//2;combined.paste(im,(x,y));provenance.append(dict(src,source_sha256=sha(ROOT/src['out']),actual_size=list(im.size),assembly_offset=[x,y]));y+=im.height
  overrides=[]
  for change in job.get('frame_overrides',[]):
   data=np.asarray(combined)
   if np.mean(data[:,:,3]<8)<=.30:combined=cyan_matte(combined)
   existing=components(combined,job['metadata']['count'],job['metadata']['columns'])
   replacement=Image.open(ROOT/change['source']).convert('RGBA');a=np.asarray(replacement)
   if np.mean(a[:,:,3]<8)<=.30:replacement=cyan_matte(replacement)
   chosen=components(replacement,change['count'],change['columns'])[change['source_index']][1]
   b,_=existing[change['index']]
   combined.paste((0,0,0,0),b)
   at=(round((b[0]+b[2]-chosen.width)/2),b[3]-chosen.height)
   combined.alpha_composite(chosen,at)
   overrides.append(dict(change,source_sha256=sha(ROOT/change['source']),placement=list(at),replaced_bounds=list(b)))
  combined.save(ROOT/job['out'])
  record=dict(id=job['id'],status='assembled',route='Lossless vertical assembly of generated six-frame source sheets',output=job['out'],actual_size=list(combined.size),sources=provenance,frame_overrides=overrides,sha256=sha(ROOT/job['out']))
  (OUT/'records'/(job['id']+'.json')).write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
  print('ASSEMBLED',job['id'],combined.size)
if __name__=='__main__':main()
