"""Split long action clips into <=6-frame requests without changing game timing."""
import copy,json,math,sys
from pathlib import Path
from PIL import Image
ROOT=Path.cwd();sys.path.insert(0,str(ROOT/'tools'))
from review_nezuko_awakening_v7 import parts_for
OUT=ROOT/'output/imagegen/awakening-v7'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,d):p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
jobs=read(OUT/'jobs.json');basejobs=read(ROOT/'output/imagegen/awakening-v6/jobs.json');baseby={j['id']:j for j in basejobs};generations=[]
maxjobs=read(OUT/'max-pilot.json')
for job in jobs:
 clip=job['metadata']['clip'];count=job['metadata']['count']
 if clip=='idle':continue
 if count<=6:
  generations.append(copy.deepcopy(job));continue
 if clip=='awakened_combo':segments=maxjobs
 else:
  original=baseby[job['id']];_,parts=parts_for(original);segments=[]
  for part in range(math.ceil(count/6)):
   indices=list(range(part*6,min(count,part*6+6)));n=len(indices);rows=math.ceil(n/3)
   guide=Image.new('RGB',(1536,rows*512),(0,255,255))
   for pos,index in enumerate(indices):
    sprite=parts[index][1];ratio=440/max(sprite.size);sprite=sprite.resize((round(sprite.width*ratio),round(sprite.height*ratio)),Image.Resampling.LANCZOS)
    guide.paste(sprite,((pos%3)*512+(512-sprite.width)//2,(pos//3)*512+486-sprite.height),sprite)
   ref=OUT/'references'/(job['id']+'-part'+str(part)+'.png');guide.save(ref)
   segment=copy.deepcopy(job);segment['id']=job['id']+'-part'+str(part);segment['group']='awakening';segment['out']='output/imagegen/awakening-v7/raw/'+segment['id']+'.png';segment['prompt']='output/imagegen/awakening-v7/prompts/'+segment['id']+'.txt';segment['references']=[job['references'][0],ref.relative_to(ROOT).as_posix()];segment['size']=f'1536x{rows*512}'
   segment['metadata'].update(count=n,columns=3,rows=rows,frame_indices=indices)
   prompt=(ROOT/job['prompt']).read_text(encoding='utf-8')
   prompt=prompt.replace(f'{count} poses in {job["metadata"]["columns"]} columns x {job["metadata"]["rows"]} rows',f'{n} poses in 3 columns x {rows} rows')
   start=prompt.index('Sheet geometry:');prompt=prompt[:start]+f'''Sheet geometry: 1536 x {rows*512}, 3 equal columns x {rows} equal rows, EXACTLY {n} separate full-body figures in row-major order, corresponding to animation frames {indices}. Keep the first/last pose in this segment as shown in image 2; do not add an idle or reset between segments. Each figure is the SAME anatomical model from image 1, with upright crown-to-sole height about 440 pixels and skull crown-to-chin 72 pixels. Never copy a short body or large head from choreography image 2. Generous gutters; full fingers, hair and sandals; no cropped parts. Crouches and horizontal poses must leave extra empty space rather than grow to fill the cell. Flat CYAN #00ffff background; no aura, effects, floor, text or extra figures.\n'''
   (ROOT/segment['prompt']).write_text(prompt,encoding='utf-8');segments.append(segment)
 job['source_sheets']=[dict(id=s['id'],out=s['out'],indices=s['metadata']['frame_indices'],columns=s['metadata']['columns'],rows=s['metadata']['rows'],prompt=s['prompt'],references=s['references']) for s in segments]
 job['out']='output/imagegen/awakening-v7/raw/'+job['id']+'-assembled.png';job['metadata'].update(columns=3,rows=math.ceil(count/3));job['group']='assembled'
 generations.extend(segments)
save(OUT/'generation-jobs.json',generations);save(OUT/'jobs.json',jobs)
print(len(generations),'generation jobs including the existing pilots; 300 dynamic frames.')
