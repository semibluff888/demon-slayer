"""Offline, repeatable motion fixes. Original atlas pages remain untouched."""
import copy, hashlib, json
from pathlib import Path
import numpy as np
from PIL import Image
from build_roster_art import matte, components
from build_awakening_art import clean
from review_motion_fixes import sheet
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/motion-fixes-v1'
TARGETS={'nezuko/awakening':['blood_kick','spinning_kick','blood_burst','throw_forward','throw_success'], 'nezuko':['blood_burst','throw_forward','throw_success'], 'zenitsu':['throw_success'], 'zenitsu/awakening':['throw_success'], 'akaza':['throw_forward','throw_success'], 'akaza/awakening':['throw_forward','throw_success']}
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def baseline(key):
 d=ROOT/'art/characters'/key;b=OUT/'baseline'/key
 if not (b/'atlas.json').exists():
  m=read(d/'atlas.json');b.mkdir(parents=True,exist_ok=True)
  for c in set(TARGETS[key]+['idle','throw_forward']):
   for i,e in enumerate(m['clips'][c]['frames']):
    x,y,w,h=e['region'];Image.open(d/e['texture']).convert('RGBA').crop((x,y,x+w,y+h)).save(b/f'{c}-{i}.png')
  save(b/'atlas.json',m)
 m=read(b/'atlas.json');frames={c:[(Image.open(b/f'{c}-{i}.png').convert('RGBA'),tuple(e['offset'])) for i,e in enumerate(m['clips'][c]['frames'])] for c in set(TARGETS[key]+['idle','throw_forward'])}
 return m,frames

def scale(pair,factor,anchor=448):
 im,(x,y)=pair;w,h=im.size;sz=(round(w*factor),round(h*factor))
 return im.resize(sz,Image.Resampling.LANCZOS),(round(anchor+(x-anchor)*factor),y+h-sz[1])
def flip(pair,anchor=448):
 im,(x,y)=pair;return im.transpose(Image.Transpose.FLIP_LEFT_RIGHT),(2*anchor-x-im.width,y)

def pack(key,m,frames):
 d=ROOT/'art/characters'/key;page=Image.new('RGBA',(2048,2048));x=y=2;rh=0;page_id=0
 for c in TARGETS[key]:
  entries=[]
  for im,offset in frames[c]:
   if x+im.width+2>2048:x=2;y+=rh+4;rh=0
   if y+im.height+2>2048:
    page.save(d/f'motion-fixes-{page_id}.png');page_id+=1;page=Image.new('RGBA',(2048,2048));x=y=2;rh=0
   assert min(offset)>=0 and all(offset[a]+im.size[a]<=m['canvas_size'][a] for a in [0,1])
   page.alpha_composite(im,(x,y));entries.append(dict(texture=f'motion-fixes-{page_id}.png',region=[x,y,*im.size],offset=list(offset)))
   x+=im.width+4;rh=max(rh,im.height)
  m['clips'][c]['frames']=entries
 page.save(d/f'motion-fixes-{page_id}.png')
 current=read(d/'atlas.json')
 for c in TARGETS[key]:current['clips'][c]=m['clips'][c]
 current['motion_revision']='motion-fixes-v1';save(d/'atlas.json',current)
 save(OUT/'imports'/f'{key.replace("/","-")}.json',dict(clips={c:m['clips'][c] for c in TARGETS[key]}))

def akaza_poses():
 raw=Image.open(OUT/'raw/akaza-throw.png').convert('RGBA');a=np.array(raw)
 # Remove only the generated white cell dividers. Component extraction retains
 # hands extending into the neighboring cell's green gutter.
 yy,xx=np.indices(a.shape[:2]);grid=(abs(xx-383)<5)|(abs(xx-767)<5)|(abs(xx-1151)<5)|(abs(yy-511)<5)
 a[:,:,3][grid & (a[:,:,:3].min(axis=2)>80)]=0
 parts=components(matte(Image.fromarray(a),(0,255,0)),8,4)
 roots=[177,564,964,1374,194,582,963,1364]
 heads=[91,88,90,91,90,90,89,91]
 poses=[];records=[]
 for i,(bounds,im) in enumerate(parts):
  factor=70/heads[i];sz=tuple(round(v*factor) for v in im.size);off=(round(448-(roots[i]-bounds[0])*factor),569-sz[1])
  poses.append((im.resize(sz,Image.Resampling.LANCZOS),off));records.append(dict(bounds=bounds,head_length=heads[i],target_head_length=70,scale=factor,root_x=roots[i],offset=off,size=sz))
 save(OUT/'imports/akaza-generated.json',dict(source_sha256=hashlib.sha256((OUT/'raw/akaza-throw.png').read_bytes()).hexdigest(),frames=records))
 return poses

def main():
 generated=akaza_poses()
 for key in TARGETS:
  m,f=baseline(key);idle=f['idle'][0]
  if key=='nezuko/awakening':
   for i,v in {1:.94,3:.94,5:.93,6:.94}.items():f['blood_kick'][i]=scale(f['blood_kick'][i],v)
   for c in ['spinning_kick','blood_burst']:f[c][-1]=idle
   # A hip hinge shortens the silhouette; calibrate the small head/limbs too.
   f['throw_forward'][8]=scale(f['throw_forward'][8],1.12)
   f['throw_success'][8]=flip(f['throw_forward'][8])
  elif key=='nezuko':
   f['blood_burst']=[scale(p,1.06) for p in f['blood_burst']]
   f['blood_burst'][0]=idle;f['blood_burst'][-1]=idle
   f['throw_forward'][0]=idle;f['throw_forward'][-1]=idle
   # Keep two authored turning drawings between the shared grab and mirrored slam.
   old=f['throw_success'];f['throw_success']=f['throw_forward'][:4]+[scale(old[4],1.06),scale(old[5],1.06)]+[flip(p) for p in f['throw_forward'][6:]]
  elif key.startswith('zenitsu'):
   # The turn culminates at pose 5. All subsequent body hinges must face the
   # victim's landing side, including recovery and final guard.
   for i in [5,6,8,9,10,11]:f['throw_success'][i]=flip(f['throw_success'][i])
  elif key.startswith('akaza'):
   seq=[idle,*generated[1:7],idle]
   f['throw_forward']=seq;f['throw_success']=seq[:3]+[flip(p) for p in seq[3:]]
   for c in TARGETS[key]:m['clips'][c]['timeline']=[0,3,8,10,15,20,23,29]
  pack(key,m,f)
 for cid,form,clips in [('nezuko','awakening',['idle','blood_kick','spinning_kick','blood_burst','throw_forward','throw_success']),('nezuko','',['idle','blood_burst','throw_forward','throw_success']),('akaza','',['idle','throw_forward','throw_success']),('zenitsu','',['idle','throw_forward','throw_success'])]:sheet(cid,form,clips,'after')
 print('Built motion corrections for',', '.join(TARGETS))
if __name__=='__main__':main()
