# coding: utf-8
"""Apply calibrated single-clip replacements without changing other packed artwork."""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from PIL import Image,ImageDraw
from build_roster_art import matte,components
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/uppercut-v1'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_name(p.name+'.building')
 tmp.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8');tmp.replace(p)
def review():
 for job in read(OUT/'jobs.json'):
  path=ROOT/job['out']
  if not path.exists():raise ValueError('No generated output: '+job['id'])
  im=Image.open(path);parts=components(matte(im,[0,255,0]),9,3)
  target=OUT/'review';target.mkdir(exist_ok=True)
  sheet=Image.new('RGB',(1536,1536),'#18202e');draw=ImageDraw.Draw(sheet)
  for i,(box,pose) in enumerate(parts):
   pose.save(target/(str(i)+'.png'))
   display=pose.copy();display.thumbnail((480,455),Image.Resampling.LANCZOS)
   x=(i%3)*512+(512-display.width)//2;y=(i//3)*512+490-display.height
   sheet.paste(display,(x,y),display);draw.text(((i%3)*512+8,(i//3)*512+8),str(i)+' '+str(box),fill='white')
  sheet.save(target/'cutout-review.jpg',quality=97)
  print(job['id'],im.size,'sha256',hashlib.sha256(path.read_bytes()).hexdigest(),'boxes',[p[0] for p in parts])
def apply_character_overrides(character):
 if not (OUT/'calibration.json').exists():return
 calibration=read(OUT/'calibration.json')
 for job in read(OUT/'jobs.json'):
  if job['metadata']['character']!=character or job['id'] not in calibration:continue
  config=calibration[job['id']]
  if not config.get('approved'):continue
  source=ROOT/job['out'];sha=hashlib.sha256(source.read_bytes()).hexdigest()
  if sha!=config['source_sha256']:raise ValueError('Override calibration is stale')
  target=ROOT/'art/characters'/character;atlas=read(target/'atlas.json')
  clip=job['metadata']['clip'];previous=OUT/'imports'/(job['id']+'-previous-clip.json')
  if not previous.exists():save(previous,atlas['clips'][clip])
  original=Image.open(source);parts=components(matte(original,[0,255,0]),9,3)
  canvas_size=tuple(atlas['canvas_size']);anchor=atlas['feet_anchor']
  page=Image.new('RGBA',(2048,2048));px=py=2;row_height=0;entries=[];records=[]
  for i,(crop,pose) in enumerate(parts):
   scale=config['base_scale']*config['frame_multipliers'][i]
   rx=config['root_x'][i]-crop[0]
   if str(i) in config['pelvis_y']:
    ry=config['pelvis_y'][str(i)]-crop[1]+34/70*atlas['source_height']/scale
   else:ry=pose.height-1
   resized=pose.resize((round(pose.width*scale),round(pose.height*scale)),Image.Resampling.LANCZOS)
   offset=(round(anchor[0]-rx*scale),round(anchor[1]-ry*scale))
   if min(offset)<0 or offset[0]+resized.width>canvas_size[0] or offset[1]+resized.height>canvas_size[1]:raise ValueError('Clipped replacement frame '+str(i))
   if px+resized.width+2>2048:px=2;py+=row_height+4;row_height=0
   if py+resized.height+2>2048:raise ValueError('Replacement page full')
   page.alpha_composite(resized,(px,py))
   entries.append(dict(texture='uppercut-'+clip+'.png',region=[px,py,resized.width,resized.height],offset=list(offset)))
   records.append(dict(source=job['out'],crop=list(crop),scale=scale,source_root=[rx+crop[0],ry+crop[1]],source_pelvis_y=config['pelvis_y'].get(str(i)),normalized_bounds=[offset[0],offset[1],offset[0]+resized.width,offset[1]+resized.height]))
   px+=resized.width+4;row_height=max(row_height,resized.height)
  temporary=target/('uppercut-'+clip+'.building.png');page.save(temporary);temporary.replace(target/('uppercut-'+clip+'.png'))
  atlas['clips'][clip].update(frames=entries,phase_breaks=[3,6],anchor_mode='mixed')
  save(target/'atlas.json',atlas)
  save(OUT/'imports'/(job['id']+'.json'),dict(source=job['out'],source_sha256=sha,actual_size=list(original.size),canvas_size=list(canvas_size),feet_anchor=anchor,frames=records))
  record=read(OUT/'records'/(job['id']+'.json'));record.update(actual_size=list(original.size),sha256=sha,accepted=True,review_scope='Nine unique drawings, consistent anatomy, grounded and airborne registration, rendered game review.')
  save(OUT/'records'/(job['id']+'.json'),record)
  print('Applied registered uppercut replacement:',character,clip)
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--review',action='store_true');args=parser.parse_args()
 if args.review:review()
 else:
  for cid in sorted({j['metadata']['character'] for j in read(OUT/'jobs.json')}):apply_character_overrides(cid)
if __name__=='__main__':main()
