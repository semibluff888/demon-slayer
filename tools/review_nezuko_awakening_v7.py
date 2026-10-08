"""Fixed-ruler source review: no individual sprite fitting."""
import argparse,json,math,sys
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from build_awakening_art import cyan_matte,clean
from build_roster_art import components
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/awakening-v7'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def parts_for(job):
 raw=Image.open(ROOT/job['out']).convert('RGBA');a=np.asarray(raw)
 keyed=cyan_matte(raw)
 return raw,[(b,clean(s,True)) for b,s in components(keyed,job['metadata']['count'],job['metadata']['columns'])]
def main():
 global OUT
 p=argparse.ArgumentParser();p.add_argument('--id');p.add_argument('--source-dir',default='output/imagegen/awakening-v7');args=p.parse_args();OUT=ROOT/args.source_dir
 jobs=read(OUT/'jobs.json');selection=read(OUT/'selected.json') if (OUT/'selected.json').exists() else {}
 font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',18)
 for base in jobs:
  job=dict(base);job.update(selection.get(base['id'],{}))
  if (args.id and base['id']!=args.id) or not (ROOT/job['out']).exists():continue
  raw,parts=parts_for(job);cols=job['metadata']['columns'];rows=job['metadata']['rows']
  sheet=Image.new('RGB',raw.size,'#182438');draw=ImageDraw.Draw(sheet)
  for i,(b,s) in enumerate(parts):
   sheet.paste(s,b[:2],s);draw.text((int((i%cols)*raw.width/cols)+8,int((i//cols)*raw.height/rows)+8),str(i),font=font,fill='white')
   for x in range(0,raw.width,50):
    if b[0]-20<x<b[2]+20:draw.line((x,b[1]-6,x,b[1]),fill='#628098');draw.text((x,b[1]-26),str(x),font=font,fill='#8098b0')
  sheet.save(OUT/'review'/(base['id']+'-source.jpg'),quality=94)
  data={'actual_size':list(raw.size),'parts':[{'crop':list(b),'size':list(s.size)} for b,s in parts]}
  (OUT/'review'/(base['id']+'-parts.json')).write_text(json.dumps(data,indent=2),encoding='utf-8')
  print(base['id'],raw.size)
if __name__=='__main__':main()
