"""Deterministic keying, pose registration, and immutable awakening atlas packing."""
import argparse,copy,hashlib,json,math,time
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from build_roster_art import matte,components
from awakening_anatomy import calibrated_frames,register
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/awakening-v1'
def save(path,data):
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
def cyan_matte(image):
 """Remove bright cyan while retaining Tanjiro's darker teal checks."""
 a=np.asarray(image.convert('RGBA')).astype(np.float32)
 rgb=a[:,:,:3];dominance=np.minimum(rgb[:,:,1],rgb[:,:,2])-rgb[:,:,0]
 coverage=1-np.clip((dominance-140)/70,0,1)
 alpha=coverage*a[:,:,3]/255
 clean=np.clip((rgb-np.array([0,255,255])*(1-coverage[:,:,None]))/np.maximum(coverage[:,:,None],.001),0,255)
 result=np.dstack([clean,alpha*255]).astype(np.uint8)
 result[alpha<.02]=0
 return Image.fromarray(result,'RGBA')

def selected_jobs():
 jobs=json.loads((OUT/'jobs.json').read_text(encoding='utf-8'))
 selection_path=OUT/'selected.json'
 selected=json.loads(selection_path.read_text(encoding='utf-8')) if selection_path.exists() else {}
 for job in jobs:
  job['base_id']=job['id']
  job.update(selected.get(job['id'],{}))
 return jobs

def clean(cell,despill=False,return_bounds=False):
 native=np.asarray(cell.convert('RGBA'))
 image=cell.convert('RGBA')
 data=np.array(image)
 n,labels,stats,_=cv2.connectedComponentsWithStats((data[:,:,3]>130).astype(np.uint8),8)
 if n<2:raise ValueError('Missing figure')
 principal=1+int(np.argmax(stats[1:,4]))
 area=stats[principal,4]
 px,py,pw,ph,_=stats[principal]
 keep=np.zeros(labels.shape,np.uint8)
 for k in range(1,n):
  x,y,w,h,part_area=stats[k]
  distance=max(px-(x+w),x-(px+pw),0)**2+max(py-(y+h),y-(py+ph),0)**2
  if part_area>=max(6,area*.0006) and distance<=20**2:keep[labels==k]=1
 keep=cv2.dilate(keep,np.ones((3,3),np.uint8))
 data[:,:,3]*=keep
 if despill:
  edge=cv2.dilate((data[:,:,3]<20).astype(np.uint8),np.ones((5,5),np.uint8))>0
  rgb=data[:,:,:3].astype(np.int16)
  cyan=(np.minimum(rgb[:,:,1],rgb[:,:,2])-rgb[:,:,0]>30)&edge&(data[:,:,3]>0)
  # Thin cyan fringe becomes a neutral ink contour; interior teal cloth is untouched.
  for channel in [1,2]:data[:,:,channel][cyan]=np.minimum(data[:,:,channel][cyan],np.clip(rgb[:,:,0][cyan]+18,0,255))
 image=Image.fromarray(data,'RGBA')
 bounds=image.getbbox()
 if not bounds or (bounds[2]-bounds[0])<15 or (bounds[3]-bounds[1])<15:raise ValueError('Incomplete sprite')
 return (image.crop(bounds),bounds) if return_bounds else image.crop(bounds)
def save_page(page,path):
 # Atomic replacement keeps Godot from reading a partially written PNG on Windows.
 temporary=path.with_name(path.stem+'.building.png')
 page.save(temporary)
 for attempt in range(5):
  try:
   temporary.replace(path)
   break
  except PermissionError:
   if attempt==4:raise
   time.sleep(.4*(attempt+1))

def pack(directory,manifest,clips):
 result={k:copy.deepcopy(v) for k,v in manifest.items() if k!='clips'}
 result['revision']=OUT.name;result['clips']={}
 sprites=[]
 for clip,item in clips.items():
  meta=copy.deepcopy(item['meta']);meta.pop('frames',None);meta['frames']=[None]*len(item['frames'])
  result['clips'][clip]=meta
  for index,(image,offset) in enumerate(item['frames']):sprites.append((clip,index,image,offset))
 sprites.sort(key=lambda s:s[2].height,reverse=True)
 directory.mkdir(parents=True,exist_ok=True)
 page=Image.new('RGBA',(2048,2048));page_index=0;x=y=2;row_h=0
 for clip,index,sprite,offset in sprites:
  if x+sprite.width+2>2048:x=2;y+=row_h+4;row_h=0
  if y+sprite.height+2>2048:
   save_page(page,directory/f'atlas-{page_index}.png');page_index+=1;page=Image.new('RGBA',(2048,2048));x=y=2;row_h=0
  page.alpha_composite(sprite,(x,y))
  result['clips'][clip]['frames'][index]=dict(texture=f'atlas-{page_index}.png',region=[x,y,sprite.width,sprite.height],offset=list(offset))
  x+=sprite.width+4;row_h=max(row_h,sprite.height)
 save_page(page,directory/f'atlas-{page_index}.png')
 save(directory/'atlas.json',result)
 used={entry['texture'] for clip in result['clips'].values() for entry in clip['frames']}
 for stale in directory.glob('atlas-*.png'):
  if stale.name not in used:
   for unused in [stale,stale.with_name(stale.name+'.import')]:
    for attempt in range(5):
     try:
      if unused.exists():unused.unlink()
      break
     except PermissionError:
      if attempt==4:raise
      time.sleep(.4*(attempt+1))
 return result
def source_sprite(directory,entry,cache):
 if entry['texture'] not in cache:cache[entry['texture']]=Image.open(directory/entry['texture']).convert('RGBA')
 x,y,w,h=entry['region']
 return cache[entry['texture']].crop((x,y,x+w,y+h)),tuple(entry['offset'])
def enhance_akaza(image):
 data=np.array(image).astype(np.float32)
 rgb=data[:,:,:3]
 blue=(rgb[:,:,2]>rgb[:,:,0]*1.15)&(rgb[:,:,2]>rgb[:,:,1]*1.03)&(data[:,:,3]>0)
 gold=(rgb[:,:,0]>155)&(rgb[:,:,1]>110)&(rgb[:,:,2]<rgb[:,:,1]*.60)&(data[:,:,3]>0)
 rgb[blue]=rgb[blue]*.65+np.array([65,179,240])*.35
 rgb[gold]=rgb[gold]*.65+np.array([255,221,104])*.35
 return Image.fromarray(np.clip(data,0,255).astype(np.uint8),'RGBA')
def review(cid,clip,old,new,canvas_size):
 tile=(400,280);cols=6;rows=math.ceil(len(new)/3)
 sheet=Image.new('RGB',(tile[0]*cols,tile[1]*rows),'#1c2334');draw=ImageDraw.Draw(sheet)
 for i,(before,after) in enumerate(zip(old,new)):
  for side,pair in enumerate([before,after]):
   image,offset=pair
   canvas=Image.new('RGBA',canvas_size);canvas.alpha_composite(image,offset)
   canvas=canvas.resize((400,250),Image.Resampling.LANCZOS)
   at=((i%3)*800+side*400,(i//3)*280+25)
   sheet.paste(canvas,at,canvas);draw.text((at[0]+8,at[1]-20),f'{cid} {clip} #{i} '+('BASE' if side==0 else 'AWAKEN'),fill='white')
 path=OUT/'review'/f'{cid}-{clip}.jpg';sheet.save(path,quality=90)
def main():
 global OUT
 p=argparse.ArgumentParser();p.add_argument('--partial',action='store_true');p.add_argument('--character');p.add_argument('--source-dir',default='output/imagegen/awakening-v1');a=p.parse_args()
 OUT=ROOT/a.source_dir
 jobs=selected_jobs()
 if a.character:jobs=[j for j in jobs if j['metadata']['character']==a.character]
 missing=[j['id'] for j in jobs if not (ROOT/j['out']).exists()]
 if missing and not a.partial:raise SystemExit('Missing generated sources: '+', '.join(missing))
 summary=[]
 for cid in sorted(set(j['metadata']['character'] for j in jobs)):
  directory=ROOT/'art/characters'/cid
  manifest=json.loads((directory/'atlas.json').read_text(encoding='utf-8-sig'));cache={};clips={}
  round_path=directory/'round-atlas.json'
  if round_path.exists():manifest['clips'].update(json.loads(round_path.read_text(encoding='utf-8-sig'))['clips'])
  for clip,meta in manifest['clips'].items():
   frames=[source_sprite(directory,e,cache) for e in meta['frames']]
   if cid=='akaza':frames=[(enhance_akaza(image),offset) for image,offset in frames]
   clips[clip]=dict(meta=meta,frames=frames)
  baseline=None;baseline_cache={}
  if (OUT/'baseline/atlas.json').exists():baseline=json.loads((OUT/'baseline/atlas.json').read_text(encoding='utf-8-sig'))
  generated=0
  for job in jobs:
   if job['metadata']['character']!=cid or not (ROOT/job['out']).exists():continue
   record_path=OUT/'records'/(job['id']+'.json')
   record=json.loads(record_path.read_text(encoding='utf-8-sig'))
   if record.get('status') not in ['generated','assembled']:raise ValueError('Inspect uncertain request '+job['id'])
   meta=job['metadata'];clip=meta['clip'];cols=meta['columns'];rows=meta['rows'];cw,ch=meta['cell']
   profile=meta.get('registration_profile','legacy')
   if profile=='preserve-v6-idle':
    old_meta=baseline['clips'][clip]
    clips[clip]=dict(meta=old_meta,frames=[source_sprite(OUT/'baseline',e,baseline_cache) for e in old_meta['frames']])
    prior=json.loads((ROOT/'output/imagegen/awakening-v6/imports'/('nezuko-'+clip+'.json')).read_text(encoding='utf-8'))
    prior['registration_profile']='preserve-v6-idle';save(OUT/'imports'/(job['base_id']+'.json'),prior);generated+=1
    continue
   anatomical=profile=='idle-head-ruler-v7'
   if anatomical:
    if a.partial and (not (OUT/'anatomy-calibration.json').exists() or job['base_id'] not in json.loads((OUT/'anatomy-calibration.json').read_text(encoding='utf-8'))['clips']):continue
    target_head,anatomy_model=calibrated_frames(ROOT,OUT,job)
   raw=Image.open(ROOT/job['out']).convert('RGBA')
   if job.get('source_rotation'):raw=raw.rotate(job['source_rotation'])
   native=np.asarray(raw)
   # Preserve the historical v1 keying; later revisions use costume-safe cyan removal.
   keyed=cyan_matte(raw) if anatomical else (raw if np.mean(native[:,:,3]<8)>.30 else (cyan_matte(raw) if OUT.name!='awakening-v1' else matte(raw,(0,255,255))))
   # Segment complete bodies before ordering cells: airborne poses can cross a grid boundary.
   parts=components(keyed,meta['count'],cols)
   new=[];registration=[]
   original=clips['idle' if clip=='awakening_start' else clip]['frames']
   if clip=='awakening_start':original=[original[0]]*meta['count']
   for index in range(meta['count']):
    source_crop,sprite=parts[index]
    sprite=clean(sprite,OUT.name!='awakening-v1')
    bounds=meta['source_bounds'][index];w=bounds[2]-bounds[0];h=bounds[3]-bounds[1]
    details={}
    if anatomical:
     old_sprite,old_offset=source_sprite(OUT/'baseline',baseline['clips'][clip]['frames'][index],baseline_cache)
     scale,size,offset,details=register(sprite,index,target_head,anatomy_model,old_sprite,old_offset,bounds)
     sprite=sprite.resize(size,Image.Resampling.LANCZOS)
    else:
     # Uniform anatomical calibration, never independent width/height stretching.
     horn_allowance=1.035 if cid=='nezuko' and h>w and OUT.name=='awakening-v1' else 1.0
     if OUT.name!='awakening-v1' and clip in ['idle','walk','walk_back','awakening_start','guard']:
      scale=h/sprite.height
     else:
      scale=max(w,h)*horn_allowance/max(sprite.size)
     center_x=(bounds[0]+bounds[2])/2
     available_width=2*min(center_x,manifest['canvas_size'][0]-center_x)
     scale=min(scale,available_width/sprite.width,bounds[3]/sprite.height)
     size=(max(1,round(sprite.width*scale)),max(1,round(sprite.height*scale)))
     sprite=sprite.resize(size,Image.Resampling.LANCZOS)
     offset=(round((bounds[0]+bounds[2]-size[0])/2),bounds[3]-size[1])
    if min(offset)<0 or offset[0]+size[0]>manifest['canvas_size'][0] or offset[1]+size[1]>manifest['canvas_size'][1]:raise ValueError('Pose overflow '+job['id']+':'+str(index))
    new.append((sprite,offset));registration.append(dict(scale=scale,offset=offset,size=size,source_bounds=bounds,source_crop=list(source_crop),**details))
   new_meta=copy.deepcopy(meta['original_clip'])
   if clip=='awakening_start':new_meta.update(loop=False,fps=20,phase_breaks=[2,4])
   clips[clip]=dict(meta=new_meta,frames=new)
   review(cid,clip,original,new,tuple(manifest['canvas_size']))
   save(OUT/'imports'/(job['base_id']+'.json'),dict(job_id=job['id'],source=job['out'],source_rotation=job.get('source_rotation',0),source_sha256=hashlib.sha256((ROOT/job['out']).read_bytes()).hexdigest(),frames=registration))
   generated+=1
  if not generated:continue
  result=pack(directory/'awakening',manifest,clips)
  summary.append(dict(character=cid,generated_clips=generated,clips=len(result['clips']),frames=sum(len(m['frames']) for m in result['clips'].values())))
  print('BUILT',summary[-1],flush=True)
 if a.character:
  prior=json.loads((OUT/'imports'/'summary.json').read_text(encoding='utf-8')) if (OUT/'imports'/'summary.json').exists() else []
  summary=[row for row in prior if row['character']!=a.character]+summary
 save(OUT/'imports'/'summary.json',sorted(summary,key=lambda row:row['character']))
 links=['<a href="'+p.name+'">'+p.stem+'</a>' for p in sorted((OUT/'review').glob('*.jpg'))]
 (OUT/'review'/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Awakening pose review</title><style>body{background:#171d2b;color:#eee;font:16px system-ui}a{display:inline-block;color:#adcefa;margin:12px}</style><h1>Base / Awakening · registered frames</h1>'+''.join(links),encoding='utf-8')
if __name__=='__main__':main()
