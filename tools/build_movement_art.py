"""Rebuild calibrated character atlases and the continuous courtyard offline."""
import argparse
from pathlib import Path
from PIL import Image
import process_anime_art as pipeline

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'output/imagegen/anime-v2'
# One anatomy-based multiplier per source clip, never per silhouette/frame.
SCALE_ADJUST = {
 'tanjiro': {'crouch_light':0.88,'water_wheel':0.91,'water_slash':0.97,'guard_low':0.96},
 'zenitsu': {'crouch_light':0.94,'thunder':0.91,'iai':0.96,'guard_low':0.97},
}
def calibrate():
 jobs = pipeline.load_json(OUT/'jobs.json',[])
 calibration = pipeline.load_json(OUT/'calibration.json',{})
 for character in ('tanjiro','zenitsu'):
  latest={}
  for job in jobs:
   if job['metadata'].get('character')==character and job['group']!='failed-attempts':
    if pipeline.load_json(OUT/'records'/(job['id']+'.json'),{}).get('status')=='generated':
     latest[job['metadata']['clip']]=job
  for clip,job in latest.items():
   with Image.open(ROOT/job['out']) as im:
    cell_h=im.height/job['metadata']['rows']
   current=calibration.setdefault(job['id'],{})
   if 'movement-v3' in job['id']:
    fraction = 1.05 if clip.startswith('dash') else 1.08 if clip.startswith('jump_') else 0.99 if clip=='thrown' else 0.93
    current.setdefault('standing_height',cell_h*fraction)
    current['root_fraction']=0.5
    current.setdefault('note','Registered against existing idle head/hand/limb proportions; one fixed scale across the entire clip. Rotating poses use a pelvis root.')
    if clip=='throw_success':
     current['mirror_frames']=[4,7,8,9]
   else:
    # Keep existing measured sweep overrides, explicitly record all other sources.
    current.setdefault('standing_height',cell_h*0.93/SCALE_ADJUST[character].get(clip,1.0))
    current.setdefault('note','Idle-referenced clip-wide anatomy calibration; no pose-dependent scaling.')
 # Pelvis coordinates measured on the actual returned sheet, not the requested size.
 calibration['tanjiro-jump_forward-movement-v3']['pelvis']={str(i):p for i,p in enumerate([
  [.36,.55],[.39,.54],[.48,.48],[.57,.42],[.51,.38],[.51,.45],[.49,.53],[.60,.62]])}
 calibration['tanjiro-thrown-movement-v3']['pelvis']={str(i):p for i,p in enumerate([
  [.52,.65],[.60,.65],[.52,.67],[.64,.68],[.64,.37],[.55,.52],[.49,.51],[.53,.42],[.59,.52],[.56,.56],[.55,.69],[.55,.76]])}
 pipeline.save_json(OUT/'calibration.json',calibration)

def extended_stage():
 from build_continuous_stage import build_stage
 build_stage()

def main():
 parser=argparse.ArgumentParser()
 parser.add_argument('--part',choices=['all','animation','stage'],default='all')
 args=parser.parse_args()
 if args.part in ('all','animation'):
  calibrate()
  pipeline.animations()
 if args.part in ('all','stage'):
  extended_stage()
 pipeline.mark_generated_dimensions()
if __name__=='__main__': main()
