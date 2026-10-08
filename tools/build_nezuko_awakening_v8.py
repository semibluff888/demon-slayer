"""Import v8 replacements while retaining every unedited v7 drawing verbatim."""
import argparse,copy,hashlib,json,math
from pathlib import Path
from PIL import Image
import build_awakening_art as atlas_builder
from build_awakening_art import clean,cyan_matte,source_sprite
from build_roster_art import components
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/imagegen/awakening-v8'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def selected_jobs():
 selection=read(OUT/'selected.json') if (OUT/'selected.json').exists() else {}
 jobs=read(OUT/'jobs.json')
 for j in jobs:j['base_id']=j['id'];j.update(selection.get(j['id'],{}))
 return jobs

def source_parts(job):
 raw=Image.open(ROOT/job['out']).convert('RGBA');pieces=[]
 for bounds,cell in components(cyan_matte(raw),job['metadata']['count'],job['metadata']['columns']):
  sprite,trim=clean(cell,True,return_bounds=True)
  pieces.append((sprite,[bounds[0]+trim[0],bounds[1]+trim[1]]))
 return pieces

def register_v8(sprite,origin,frame,model):
 # Landmarks are explicitly reviewed source-image coordinates, never a costume
 # color heuristic or roots inherited from the faulty previous animation.
 root=[frame['root'][axis]-origin[axis] for axis in [0,1]]
 if 'height' in frame:scale=float(frame['height'])/sprite.height
 else:scale=float(model['target_head_length'])/frame['head_length']
 if not math.isfinite(scale) or scale<=0:raise ValueError('Invalid reviewed scale')
 size=[max(1,round(x*scale)) for x in sprite.size]
 target_x=float(frame.get('target_x',model.get('target_x',449)))
 x=round(target_x-root[0]*scale)
 if model['anchor']=='waist':y=round(float(frame.get('target_y',model['target_y']))-root[1]*scale)
 else:y=round(float(frame.get('ground_y',569))-size[1])
 return scale,size,[x,y],dict(source_root=root,source_root_absolute=frame['root'],target_root_x=target_x,rendered_root_x=x+root[0]*scale,rendered_root_y=y+root[1]*scale,scaled_head_length=scale*frame['head_length'],anchor=model['anchor'])

def main():
 p=argparse.ArgumentParser();p.add_argument('--partial',action='store_true');args=p.parse_args()
 master=read(OUT/'master.json');manifest=read(OUT/'baseline/atlas.json');calibration=read(OUT/'motion-calibration.json');clips={};cache={};updated=[]
 for name,meta in manifest['clips'].items():clips[name]=dict(meta=meta,frames=[source_sprite(OUT/'baseline',e,cache) for e in meta['frames']])
 for job in selected_jobs():
  key=job['base_id'];clip=job['metadata']['clip'];model=calibration['clips'].get(key)
  if args.partial and (not (ROOT/job['out']).exists() or not model):continue
  if not model:raise ValueError('Missing reviewed motion model: '+key)
  if model['source_sha256']!=sha(ROOT/job['out']):raise ValueError('Stale motion landmarks: '+key)
  record=read(OUT/'records'/(job['id']+'.json'))
  if record['status'] not in ['generated','assembled']:raise ValueError('Uncertain generation: '+job['id'])
  parts=source_parts(job)
  if len(parts)!=len(model['frames']):raise ValueError('Incomplete motion landmarks: '+key)
  frames=[];registration=[]
  for i,((sprite,origin),data) in enumerate(zip(parts,model['frames'])):
   source_override=data.get('source_override')
   if source_override:
    replacement=ROOT/source_override['out']
    if sha(replacement)!=source_override['source_sha256']:raise ValueError('Stale replacement source: '+key+'/'+str(i))
    replacement_job={'out':source_override['out'],'metadata':source_override}
    sprite,origin=source_parts(replacement_job)[source_override['index']]
   scale,size,offset,details=register_v8(sprite,origin,data,model)
   if source_override:details['source_override']=source_override
   if min(offset)<0 or any(offset[j]+size[j]>manifest['canvas_size'][j] for j in [0,1]):raise ValueError('Pose overflow: '+key+'/'+str(i))
   frames.append((sprite.resize(tuple(size),Image.Resampling.LANCZOS),tuple(offset)))
   registration.append(dict(scale=scale,size=size,offset=offset,source_origin=origin,registration_profile='model-ruler-v8',**details))
  meta=copy.deepcopy(manifest['clips'][clip]);meta['fps']=model.get('fps',meta['fps']);clips[clip]=dict(meta=meta,frames=frames)
  atlas_builder.save(OUT/'imports'/(key+'.json'),dict(job_id=job['id'],source=job['out'],source_sha256=sha(ROOT/job['out']),calibration='motion-calibration.json',frames=registration));updated.append(clip)
 atlas_builder.OUT=OUT;result=atlas_builder.pack(ROOT/'art/characters/nezuko/awakening',manifest,clips)
 atlas_builder.save(OUT/'imports/summary.json',dict(updated_clips=updated,updated_frames=sum(len(clips[c]['frames']) for c in updated),preserved_clips=[c for c in clips if c not in updated],total_clips=len(clips),total_frames=sum(len(c['frames']) for c in clips.values())))
 print('BUILT v8:',len(updated),'updated clips,',sum(len(clips[c]['frames']) for c in updated),'frames; idle and MAX preserved')
if __name__=='__main__':main()
