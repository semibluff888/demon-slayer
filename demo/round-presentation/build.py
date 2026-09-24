"""Offline demo-only atlas build, calibrated sources and review sheets."""
import argparse, hashlib, json, statistics, sys
from pathlib import Path
from PIL import Image
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import process_anime_art as art
# These globals are scoped to this importer process; no production outputs.
art.OUT=HERE; art.ART=HERE/'assets'; art.REVIEW=HERE/'review'
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--available',action='store_true');args=ap.parse_args()
 jobs=json.loads((HERE/'jobs.json').read_text(encoding='utf-8'))
 calibration=art.load_json(HERE/'calibration.json',{})
 clips={}; report=[]
 for j in jobs:
  raw=ROOT/j['out']
  if not raw.exists():
   if args.available: continue
   raise FileNotFoundError(raw)
  key=j['id']; char=j['character']; clip=j['variant'].lower()+'_'+j['clip']
  with Image.open(raw) as image:
   actual=image.size
  # Measure scale once per entire sheet from its upright endpoint drawings.
  if key not in calibration:
   source=art.cutout(Image.open(raw))
   pieces=art.sprite_components(source,j['count'],j['columns'])
   candidates=pieces[:3] if j['clip']=='defeat' else pieces[:3]+pieces[-3:]
   heights=sorted(p[1].height for p in candidates)
   height=statistics.median(heights[-3:]) if len(heights)>3 else max(heights)
   calibration[key]={'standing_height':height,'root_fraction':0.5,
    'note':'One clip-wide scale from upright endpoint drawings; floor-contact Y, shared cell-center X. No per-frame bounding-box fitting.'}
   art.save_json(HERE/'calibration.json',calibration)
  metadata=dict(clip=clip,count=j['count'],columns=j['columns'],rows=3,loop=False,fps=12,root_fraction=0.5)
  frames=art.process_clip(dict(id=key,out=j['out'],metadata=metadata),calibration)
  hashes=[hashlib.sha256(im.tobytes()).hexdigest() for im in frames]
  if len(set(hashes))!=j['count']: raise ValueError('Repeated drawing in '+key)
  clips.setdefault(char,{})[clip]={'images':frames,'meta':metadata}
  record_path=HERE/'records'/f'{key}.json'
  record=art.load_json(record_path,{})
  record.update(actual_size=list(actual),sha256=hashlib.sha256(raw.read_bytes()).hexdigest(),frame_count=len(frames))
  art.save_json(record_path,record)
  report.append(dict(id=key,frames=len(frames),unique_frames=len(set(hashes)),actual_size=list(actual),scale=calibration[key]['standing_height']))
 for char, motions in clips.items():
  art.pack(char,motions);art.previews(char,motions)
 art.save_json(HERE/'asset-report.json',{'clips':report,'total_frames':sum(x['frames'] for x in report),'complete':len(report)==24})
 print('Built',len(report),'clips',sum(x['frames'] for x in report),'distinct drawings.')
if __name__=='__main__':main()
