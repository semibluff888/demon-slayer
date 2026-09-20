"""Offline phase-two source contact sheets and scale/anchor review; no service calls."""
from pathlib import Path
import argparse
from PIL import Image,ImageDraw
import process_anime_art as p
from build_movement_art import calibrate

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--raw',action='store_true');args=parser.parse_args()
 calibrate()
 jobs=p.load_json(p.OUT/'jobs.json',[]);cal=p.load_json(p.OUT/'calibration.json',{})
 for cid in ('tanjiro','zenitsu'):
  clips={}
  for job in jobs:
   if job['metadata'].get('character')!=cid or not job['group'].startswith('phase2-') or not (p.ROOT/job['out']).exists(): continue
   if p.load_json(p.OUT/'records'/(job['id']+'.json'),{}).get('status')!='generated': continue
   frames=p.process_clip(job,cal)
   clips[job['metadata']['clip']]=dict(images=frames,meta=job['metadata'])
  if clips: p.previews(cid,clips)
 p.mark_generated_dimensions()
 if args.raw:
  for cid in ('tanjiro','zenitsu'):
   files=sorted((p.OUT/'raw').glob(cid+'-*-phase2-v1.png'))
   out=Image.new('RGB',(1200,((len(files)+3)//4)*280),'#142038');draw=ImageDraw.Draw(out)
   for i,path in enumerate(files):
    im=Image.open(path).convert('RGB');im.thumbnail((294,250));x=i%4*300;y=i//4*280
    out.paste(im,(x,y+25));draw.text((x+4,y+4),path.stem.replace(cid+'-','').replace('-phase2-v1',''),fill='white')
   out.save(p.ROOT/'artifacts/phase2'/(cid+'-sources.jpg'),quality=86)
 print('Phase-two raw/trimmed contact sheets reviewed offline.')
if __name__=='__main__': main()
