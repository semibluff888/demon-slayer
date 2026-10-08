"""Small v9 pose corrections over the frozen v8 atlas. No runtime capture."""
import copy,hashlib,json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
import build_awakening_art as packer
from build_nezuko_awakening_v8 import source_parts
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/imagegen/awakening-v9'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
 manifest=read(OUT/'baseline/atlas.json');config=read(OUT/'corrections.json');cache={}
 clips={name:dict(meta=copy.deepcopy(meta),frames=[packer.source_sprite(OUT/'baseline',f,cache) for f in meta['frames']]) for name,meta in manifest['clips'].items()}
 frozen={name:list(clip['frames']) for name,clip in clips.items()}
 for clip in ['walk','walk_back']:clips[clip]['meta']['fps']=config['walk_fps']
 corrected=set()
 for clip,operations in config['poses'].items():
  if len(operations)!=len(clips[clip]['frames']):raise ValueError('Incomplete pose corrections: '+clip)
  imported=[]
  for i,op in enumerate(operations):
   source_clip=op.get('source_clip',clip);source_index=op.get('source_frame',i)
   source_revision=op.get('source_revision','baseline')
   if source_revision=='corrected':
    if source_clip not in corrected:raise ValueError('Corrected source must precede its reuse: '+source_clip)
    sprite,offset=clips[source_clip]['frames'][source_index]
   elif source_revision=='baseline':sprite,offset=frozen[source_clip][source_index]
   else:raise ValueError('Unknown source revision: '+source_revision)
   old_size=sprite.size
   sx,sy=op.get('scale',[1,1]);size=(round(sprite.width*sx),round(sprite.height*sy))
   if [sx,sy]!=[1,1]:sprite=sprite.resize(size,Image.Resampling.LANCZOS)
   pivot_x=op.get('source_waist_x',449)
   x=round(op.get('target_waist_x',pivot_x)+(offset[0]-pivot_x)*sx)
   y=op.get('ground_y',offset[1]+old_size[1])-size[1]
   if op.get('flip_x',False):
    # Match the renderer's reflection about feet_anchor, including final idle.
    sprite=sprite.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    x=2*manifest['feet_anchor'][0]-x-size[0]
   clips[clip]['frames'][i]=(sprite,(x,y))
   imported.append(dict(source_revision=source_revision,source_clip=source_clip,source_frame=source_index,source_size=list(old_size),scale=[sx,sy],size=list(size),offset=[x,y],operation=op))
  save(OUT/'imports'/('nezuko-'+clip+'.json'),dict(kind='baseline-correction',baseline='baseline/atlas.json',frames=imported))
  corrected.add(clip)
 # Composite only small hand/forearm patches. The rest of each source sheet stays exact.
 guard=config['guard'];original=ROOT/guard['original'];edited=ROOT/guard['edited']
 for path,key in [(original,'original_sha256'),(edited,'edited_sha256')]:
  if sha(path)!=guard[key]:raise ValueError('Guard patch source changed: '+str(path))
 with Image.open(original) as im:base=im.convert('RGBA')
 with Image.open(edited) as im:edit=im.convert('RGBA')
 if base.size!=edit.size:raise ValueError('Guard edit must retain source sheet coordinates')
 mask=Image.new('L',base.size,0);draw=ImageDraw.Draw(mask)
 for box in guard['patch_boxes']:draw.rectangle(box,fill=255)
 mask=mask.filter(ImageFilter.GaussianBlur(1))
 patched=Image.composite(edit,base,mask);patched_path=OUT/'raw/nezuko-guard_low-patched.png';patched.save(patched_path)
 parts=source_parts(dict(out=patched_path.relative_to(ROOT).as_posix(),metadata=dict(count=6,columns=3)))
 old=read(ROOT/'output/imagegen/awakening-v7/imports/nezuko-guard_low.json');frames=[];records=[]
 for i,((sprite,origin),entry) in enumerate(zip(parts,old['frames'])):
  scale=entry['scale'];size=tuple(entry['size']);offset=tuple(entry['offset'])
  # Hand correction cannot alter silhouette bounds, or reuse of registration is unsafe.
  expected_origin=entry['source_crop'][:2]
  if max(abs(origin[a]-expected_origin[a]) for a in [0,1])>2:raise ValueError('Guard crop moved: '+str(i))
  frames.append((sprite.resize(size,Image.Resampling.LANCZOS),offset))
  records.append(dict(size=list(size),offset=list(offset),scale=scale,source_origin=origin,patch_box=guard['patch_boxes'][i]))
 clips['guard_low']['frames']=frames
 save(OUT/'imports/nezuko-guard_low.json',dict(kind='local-hand-edit',source=patched_path.relative_to(ROOT).as_posix(),source_sha256=sha(patched_path),frames=records))
 for name,clip in clips.items():
  for index,(sprite,offset) in enumerate(clip['frames']):
   if min(offset)<0 or any(offset[a]+sprite.size[a]>manifest['canvas_size'][a] for a in [0,1]):raise ValueError('Pose outside canvas: '+name+'/'+str(index))
 packer.OUT=OUT;packer.pack(ROOT/'art/characters/nezuko/awakening',manifest,clips)
 changed=list(config['poses'])+['guard_low'];changed_frames=sum(len(clips[c]['frames']) for c in changed)
 preserved=sum(len(c['frames']) for c in clips.values())-changed_frames
 save(OUT/'imports/summary.json',dict(pixel_changed_clips=changed,pixel_changed_frames=changed_frames,pixel_preserved_frames=preserved,metadata_only_clips=['walk','walk_back'],walk_fps=config['walk_fps'],runtime_capture=False))
 print(f'BUILT v9: {changed_frames} corrected pose frames; {preserved} frames preserved; walking {config["walk_fps"]} FPS')
if __name__=='__main__':main()
