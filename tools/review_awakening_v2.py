"""Offline inspection of completed v2 jobs, never invokes generation."""
import argparse,json,math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
from build_awakening_art import cyan_matte,clean
from build_roster_art import components
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/imagegen/awakening-v2'
def main():
 global OUT
 parser=argparse.ArgumentParser();parser.add_argument('--all-frames',action='store_true');parser.add_argument('--source-dir',default='output/imagegen/awakening-v2');args=parser.parse_args()
 OUT=ROOT/args.source_dir
 all_frames={}
 jobs=json.loads((OUT/'jobs.json').read_text('utf-8'));selection=json.loads((OUT/'selected.json').read_text('utf-8')) if (OUT/'selected.json').exists() else {}
 items={};errors=[];ready=0
 for base in jobs:
  job=dict(base);job.update(selection.get(base['id'],{}))
  record=OUT/'records'/(job['id']+'.json')
  if not record.exists() or json.loads(record.read_text('utf-8-sig'))['status']!='generated':continue
  meta=job['metadata'];cid=meta['character'];ready+=1
  try:
   raw=Image.open(ROOT/job['out']).convert('RGBA')
   if job.get('source_rotation'):raw=raw.rotate(job['source_rotation'])
   keyed=raw if np.mean(np.asarray(raw)[:,:,3]<8)>.30 else cyan_matte(raw)
   parts=components(keyed,meta['count'],meta['columns'])
   tile=Image.new('RGB',(660,240),'#1b2535');draw=ImageDraw.Draw(tile)
   draw.text((9,8),base['id'],fill='#ecd6ad')
   for n,k in enumerate([0,len(parts)//2,len(parts)-1]):
    sprite=clean(parts[k][1],True);sprite.thumbnail((211,205),Image.Resampling.LANCZOS)
    tile.paste(sprite,(n*220+(220-sprite.width)//2,30+205-sprite.height),sprite)
   items.setdefault(cid,[]).append(tile)
   if args.all_frames:
    for index,part in enumerate(parts):
     frame=Image.new('RGB',(190,220),'#1b2535');d=ImageDraw.Draw(frame)
     d.text((5,6),meta['clip'][:23]+' #'+str(index),fill='#ecd6ad')
     sprite=clean(part[1],True);sprite.thumbnail((178,192),Image.Resampling.LANCZOS)
     frame.paste(sprite,((190-sprite.width)//2,24+192-sprite.height),sprite)
     all_frames.setdefault(cid,[]).append(frame)
  except Exception as e:errors.append({'job':job['id'],'error':str(e)})
 for cid,tiles in items.items():
  for page in range(math.ceil(len(tiles)/9)):
   subset=tiles[page*9:page*9+9];sheet=Image.new('RGB',(1980,240*math.ceil(len(subset)/3)),'#1b2535')
   for i,t in enumerate(subset):sheet.paste(t,((i%3)*660,(i//3)*240))
   sheet.save(OUT/'review'/f'{cid}-source-{page+1}.jpg',quality=94)
 for cid,frames in all_frames.items():
  for page in range(math.ceil(len(frames)/48)):
   subset=frames[page*48:page*48+48];sheet=Image.new('RGB',(1520,220*math.ceil(len(subset)/8)),'#1b2535')
   for i,t in enumerate(subset):sheet.paste(t,((i%8)*190,(i//8)*220))
   sheet.save(OUT/'review'/f'{cid}-all-{page+1}.jpg',quality=95)
 report={'ready':ready,'total':len(jobs),'errors':errors}
 (OUT/'review/source-check.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report))
if __name__=='__main__':main()
