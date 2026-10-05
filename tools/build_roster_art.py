# coding: utf-8
"""Offline rebuild of the expansion artwork; never calls the image service."""
import argparse,hashlib,json,math
from pathlib import Path
import numpy as np
import cv2
from PIL import Image,ImageDraw,ImageFilter,ImageOps
import process_anime_art as shared
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/roster-v1'
REVIEW=OUT/'review'
CANVAS=(1024,640);ANCHOR=(448,568)
def read(p,default=None):return json.loads(p.read_text(encoding='utf-8-sig')) if p.exists() else default
def save(p,d):
 p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(json.dumps(d,ensure_ascii=False,indent=2).encode('utf-8'))
def matte(image,key):
 a=np.asarray(image.convert('RGBA')).astype(np.float32)
 rgb=a[:,:,:3];bg=np.array(key,dtype=np.float32)
 dominance=np.minimum(rgb[:,:,1],rgb[:,:,2])-rgb[:,:,0] if key[2] else rgb[:,:,1]-np.maximum(rgb[:,:,0],rgb[:,:,2])
 coverage=1-np.clip((dominance-28)/75,0,1)
 alpha=coverage*a[:,:,3]/255
 clean=np.clip((rgb-bg*(1-coverage[:,:,None]))/np.maximum(coverage[:,:,None],0.001),0,255)
 result=np.dstack([clean,alpha*255]).astype(np.uint8)
 result[alpha<0.02]=0
 return Image.fromarray(result,'RGBA')
def update_record(job):
 p=ROOT/job['out'];record=OUT/'records'/(job['id']+'.json');d=read(record,{})
 d.update(actual_size=list(Image.open(p).size),sha256=hashlib.sha256(p.read_bytes()).hexdigest())
 save(record,d)
def ready(j):return (ROOT/j['out']).exists() and read(OUT/'records'/(j['id']+'.json'),{}).get('status')=='generated'
def static(jobs):
 calibrations=read(OUT/'portrait-calibration.json',{})
 for j in jobs:
  if j['group']!='portraits' or not ready(j):continue
  meta=j['metadata'];cid=meta['character'];target=ROOT/'art/characters'/cid;target.mkdir(parents=True,exist_ok=True)
  src=matte(Image.open(ROOT/j['out']),meta['matte'])
  if j['id'].endswith('-portrait'):
   bounds=src.getbbox();src=src.crop(bounds);src.thumbnail((1100,1600),Image.Resampling.LANCZOS)
   src.save(target/'portrait.png')
  else:
   config=calibrations.get(j['id'],{})
   if 'crop' in config:src=src.crop(tuple(config['crop']))
   if config.get('mode')=='contain':
    fitted=ImageOps.contain(src,(900,940),Image.Resampling.LANCZOS)
    src=Image.new('RGBA',(1024,1024));src.alpha_composite(fitted,((1024-fitted.width)//2,40))
   else:
    src=ImageOps.fit(src,(1024,1024),Image.Resampling.LANCZOS,centering=tuple(config.get('center',[.5,.5])))
   save(OUT/'imports'/(j['id']+'.json'),dict(source=j['out'],actual_size=list(Image.open(ROOT/j['out']).size),calibration=config,output_size=[1024,1024]))
   src.save(target/('awakened-portrait.png' if '-awakened-' in j['id'] else 'battle-portrait.png'))
   if '-awakened-' not in j['id']:
    avatar=src.crop((96,0,928,832)).resize((192,192),Image.Resampling.LANCZOS)
    bg=Image.new('RGBA',(192,192),'#382339' if cid=='nezuko' else '#15374a');bg.alpha_composite(avatar);bg.save(target/'avatar.png')
  shared.backdrop_preview(src,REVIEW/(j['id']+'-edges.jpg'));update_record(j)
 print('Portraits and avatars built',flush=True)
def effects(jobs):
 target=ROOT/'art/effects';target.mkdir(exist_ok=True)
 for j in jobs:
  if j['group']!='effects' or not ready(j):continue
  image=Image.open(ROOT/j['out']).convert('RGB');image.thumbnail((1536,1024),Image.Resampling.LANCZOS)
  key=j['id'][3:];image.save(target/(key+'.png'))
  rgb=np.asarray(image).astype(np.float32)/255
  alpha=np.max(rgb,axis=2)
  rgba=np.dstack([np.clip(rgb/np.maximum(alpha[:,:,None],.001),0,1),alpha])
  Image.fromarray((rgba*255).astype(np.uint8),'RGBA').save(target/(key+'-body.png'))
  update_record(j)
 print('Elemental textures built',flush=True)
def components(src,count,columns):
 alpha=np.asarray(src.getchannel('A'));mask=(alpha>130).astype(np.uint8)
 n,labels,stats,centers=cv2.connectedComponentsWithStats(mask,8)
 ids=sorted(range(1,n),key=lambda k:stats[k,4],reverse=True)
 if len(ids)<count or stats[ids[count-1],4]<stats[ids[0],4]*.14:raise ValueError('Insufficient complete figures')
 ids=ids[:count];ids.sort(key=lambda k:centers[k][1])
 ordered=[]
 for row in range(math.ceil(count/columns)):ordered.extend(sorted(ids[row*columns:(row+1)*columns],key=lambda k:centers[k][0]))
 result=[]
 rgba=np.asarray(src)
 for k in ordered:
  x,y,w,h,area=stats[k]
  own=(labels==k).astype(np.uint8)
  own=cv2.dilate(own,np.ones((5,5),np.uint8))
  # Nearby detached small details belong to this figure, without importing neighboring bodies.
  for other in range(1,n):
   if other in ids or stats[other,4]>area*.05:continue
   cx,cy=centers[other]
   if max(x-cx,0,cx-(x+w))**2+max(y-cy,0,cy-(y+h))**2<20**2:
    own|=cv2.dilate((labels==other).astype(np.uint8),np.ones((3,3),np.uint8))
  frame=rgba.copy();frame[:,:,3]=(frame[:,:,3]*own).astype(np.uint8)
  isolated=Image.fromarray(frame,'RGBA');b=isolated.getbbox()
  result.append((b,isolated.crop(b)))
 return result
def body_scales(job,scale_calibration):
 """Reject unreviewed/replaced sources rather than deriving anatomy from grid cells."""
 model=scale_calibration.get('clips',{}).get(job['id'])
 if model is None:raise ValueError('Missing body-scale calibration: '+job['id'])
 if model['source_sha256']!=hashlib.sha256((ROOT/job['out']).read_bytes()).hexdigest():raise ValueError('Body-scale calibration belongs to an older source: '+job['id'])
 if len(model['frame_multipliers'])!=job['metadata']['count']:raise ValueError('Incomplete drawing registration: '+job['id'])
 scales=[float(model['base_scale'])*float(factor) for factor in model['frame_multipliers']]
 if not all(math.isfinite(value) and value>0 for value in scales):raise ValueError('Invalid physical scale: '+job['id'])
 return model,scales

def clip(j,calibration,scale_calibration):
 meta=j['metadata'];src=matte(Image.open(ROOT/j['out']),meta['matte']);count=meta['count'];cols=meta['columns'];rows=meta['rows']
 parts=components(src,count,cols);cw=src.width/cols;ch=src.height/rows
 config=calibration.get(j['id'],{})
 # Cell dimensions are used only to locate roots, never to estimate body size.
 model,scales=body_scales(j,scale_calibration)
 base_scale=float(model['base_scale']);standing=340/base_scale
 frames=[];records=[]
 airborne=meta['anchor_mode']=='pelvis' and not meta['clip'].startswith('roll')
 for i,(crop,frame) in enumerate(parts):
  scale=scales[i]
  root_x=(i%cols+config.get('root_fraction',.50))*cw-crop[0]
  alpha=np.asarray(frame.getchannel('A'))
  contact=frame.height-1
  root_y=contact
  if airborne:
   pelvis=config.get('pelvis',{}).get(str(i),[.50,.55])
   root_x=(i%cols+pelvis[0])*cw-crop[0]
   root_y=(i//cols+pelvis[1])*ch-crop[1]+(34/70*340)/scale
   if (meta['clip'].startswith('thrown') and i>=8) or (meta['clip'].startswith('jump') and (i==0 or i>=count-2)):
    root_y=contact
  if str(i) in config.get('source_pelvis',{}):
   point=config['source_pelvis'][str(i)];root_x=point[0]-crop[0];root_y=point[1]-crop[1]+(34/70*340)/scale
  elif str(i) in config.get('source_roots',{}):
   point=config['source_roots'][str(i)];root_x=point[0]-crop[0];root_y=point[1]-crop[1]
  if i in config.get('ground_frames',[]):root_y=contact
  correction=config.get('anchors',{}).get(str(i),[0,0]);root_x+=correction[0];root_y+=correction[1]
  size=(max(1,round(frame.width*scale)),max(1,round(frame.height*scale)))
  frame=frame.resize(size,Image.Resampling.LANCZOS)
  at=(round(ANCHOR[0]-root_x*scale),round(ANCHOR[1]-root_y*scale))
  if at[0]<0 or at[1]<0 or at[0]+size[0]>CANVAS[0] or at[1]+size[1]>CANVAS[1]:
   raise ValueError(f'Clipped pose {j["id"]}:{i}, at={at}, size={size}; calibrate anchor')
  canvas=Image.new('RGBA',CANVAS);canvas.alpha_composite(frame,at);frames.append(canvas)
  records.append(dict(crop=list(crop),root=[root_x,root_y],scale=scale,drawing_registration=model['frame_multipliers'][i],normalized_bounds=list(canvas.getbbox())))
 cuts=config.get('phase_breaks',[count//3,count*2//3])
 if meta['clip'] in ['spinning_kick','disorder']:cuts=[3,9]
 if meta['clip'] in ['blood_burst','awakened_combo']:cuts=[3,10]
 if meta['clip']=='blue_afterglow':cuts=[2,11]
 info=dict(meta,phase_breaks=cuts)
 if meta['clip'].startswith('roll'):
  info['anchor_mode']='feet';info['timeline']=[0,1,2,4,6,9,12,15,18,20,23,26]
 if meta['clip'] in ['throw_success','throw_forward','thrown','thrown_forward']:
  info['timeline']=[0,3,5,8,10,13,15,18,20,23,26,29]
 save(OUT/'imports'/(j['id']+'.json'),dict(source=j['out'],standing_height=standing,base_scale=base_scale,scale_calibration='output/imagegen/roster-v1/scale-calibration.json',canvas_size=CANVAS,feet_anchor=ANCHOR,frames=records))
 update_record(j)
 return dict(images=frames,meta=info)
def animations(jobs,only,partial):
 calibration=read(OUT/'calibration.json',{});scale_calibration=read(OUT/'scale-calibration.json',{})
 character_ids=sorted({j['metadata']['character'] for j in jobs if j['group']=='animation'})
 for cid in character_ids:
  if only and cid!=only:continue
  selected=[j for j in jobs if j['group']=='animation' and j['metadata']['character']==cid]
  missing=[j['id'] for j in selected if not ready(j)]
  if missing and not partial:raise ValueError('Missing sources: '+', '.join(missing))
  clips={}
  for j in selected:
   if not ready(j):continue
   print('IMPORT '+j['id'],flush=True);clips[j['metadata']['clip']]=clip(j,calibration,scale_calibration)
  if clips:
   shared.pack(cid,clips)
   previous=shared.REVIEW;shared.REVIEW=REVIEW;shared.previews(cid,clips);shared.REVIEW=previous
def stages(jobs,partial):
 for sid in [j['metadata']['stage'] for j in jobs if j['group']=='foundation' and 'stage' in j['metadata']]:
  source=OUT/'raw'/(sid+'-master.png')
  if not source.exists():continue
  target=ROOT/'art/stages'/sid;target.mkdir(parents=True,exist_ok=True)
  src=Image.open(source).convert('RGB');h=round(src.width/4);top=(src.height-h)//2
  base=src.crop((0,top,src.width,top+h)).resize((6144,1536),Image.Resampling.LANCZOS)
  # A central camera-sized preview is readable on the selection cards.
  thumb=base.crop((1830,0,4314,1536));thumb.thumbnail((960,594),Image.Resampling.LANCZOS);thumb.save(target/'thumbnail.jpg',quality=94)
  detail=[j for j in jobs if j['group']=='stage-detail' and j['metadata']['stage']==sid]
  if not all(ready(j) for j in detail):
   if partial:continue
   raise ValueError('Missing registered detail for '+sid)
  acc=np.zeros((1536,6144,3),np.float32);weights=np.zeros((1536,6144),np.float32);sources=[]
  for j in detail:
   x,y,w,h=j['metadata']['target_rect'];ref=np.asarray(Image.open(ROOT/j['references'][0]).convert('RGB'))
   actual=Image.open(ROOT/j['out']).convert('RGB');paint=np.asarray(actual.resize((w,h),Image.Resampling.LANCZOS))
   warp=np.eye(2,3,dtype=np.float32);score=None
   try:
    score,warp=cv2.findTransformECC(cv2.cvtColor(ref,cv2.COLOR_RGB2GRAY),cv2.cvtColor(paint,cv2.COLOR_RGB2GRAY),warp,cv2.MOTION_AFFINE,(cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_COUNT,70,1e-5),None,5)
    if abs(warp[0,0]-1)>.08 or abs(warp[1,1]-1)>.08 or abs(warp[0,2])>60 or abs(warp[1,2])>60:raise ValueError('Stage patch shifted composition')
    paint=cv2.warpAffine(paint,warp,(w,h),flags=cv2.INTER_LINEAR|cv2.WARP_INVERSE_MAP,borderMode=cv2.BORDER_REFLECT)
   except cv2.error: raise ValueError('Could not register stage patch '+j['id'])
   wx=np.minimum(np.arange(w)+1,np.arange(w,0,-1))/192;wy=np.minimum(np.arange(h)+1,np.arange(h,0,-1))/192
   if x==0:wx[:192]=1
   if x+w==6144:wx[-192:]=1
   if y==0:wy[:192]=1
   if y+h==1536:wy[-192:]=1
   weight=np.minimum(wx,1)[None,:]*np.minimum(wy,1)[:,None]
   acc[y:y+h,x:x+w]+=paint*weight[:,:,None];weights[y:y+h,x:x+w]+=weight
   sources.append(dict(path=j['out'],actual_size=list(actual.size),rect=[x,y,w,h],registration=warp.tolist(),correlation=float(score),sha256=hashlib.sha256((ROOT/j['out']).read_bytes()).hexdigest()))
   update_record(j)
  result=Image.fromarray(np.clip(acc/np.maximum(weights[:,:,None],.001),0,255).astype(np.uint8),'RGB')
  result.save(target/'panorama.png')
  tiles=[]
  padded=np.pad(np.asarray(result),((8,8),(8,8),(0,0)),mode='edge')
  for i in range(4):
   name=f'panorama-{i}.png';Image.fromarray(padded[:,i*1536:i*1536+1552]).save(target/name)
   tiles.append(dict(texture=name,rect=[i*1536,0,1536,1536],region=[8,8,1536,1536]))
  result.crop((1830,0,4314,1536)).resize((960,594),Image.Resampling.LANCZOS).save(target/'thumbnail.jpg',quality=94)
  save(target/'stage.json',dict(revision='roster-v1',size=[6144,1536],render_size=[3168,792],world_width=960,layers=['panorama'],parallax=[1.0],tiles=tiles,sources=sources))
  result.resize((1536,384),Image.Resampling.LANCZOS).save(REVIEW/(sid+'-panorama.jpg'),quality=94)
  print('Registered stage built: '+sid,flush=True)
def main():
 p=argparse.ArgumentParser();p.add_argument('--part',choices=['all','static','animation','stage'],default='all');p.add_argument('--character');p.add_argument('--partial',action='store_true');a=p.parse_args()
 REVIEW.mkdir(parents=True,exist_ok=True);jobs=read(OUT/'jobs.json',[])
 if a.part in ['all','static']:static(jobs);effects(jobs)
 if a.part in ['all','animation']:animations(jobs,a.character,a.partial)
 if a.part in ['all','static','stage']:stages(jobs,a.partial)
if __name__=='__main__':main()
