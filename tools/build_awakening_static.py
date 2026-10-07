"""Build reviewed portrait crops and additive VFX layers from v2 CPA sources."""
import json,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
from build_awakening_art import cyan_matte
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/imagegen/awakening-v2'
CROPS={'tanjiro':(.26,0,.70,.28),'zenitsu':(.32,0,.77,.28),'nezuko':(.51,0,.78,.29)}
def main():
 for cid,crop in CROPS.items():
  target=ROOT/'art/characters'/cid/'awakening';target.mkdir(exist_ok=True)
  source=OUT/'raw'/(cid+'-model.png');raw=Image.open(source).convert('RGBA');a=np.asarray(raw)
  raw=raw if np.mean(a[:,:,3]<8)>.30 else cyan_matte(raw)
  box=tuple(round(v*(raw.width if i%2==0 else raw.height)) for i,v in enumerate(crop))
  portrait=raw.crop(box).resize((512,512),Image.Resampling.LANCZOS)
  portrait.save(target/'portrait.png')
  records={'portrait':{'source':source.relative_to(ROOT).as_posix(),'crop':box,'sha256':hashlib.sha256(source.read_bytes()).hexdigest()},'effects':[]}
  source=OUT/'raw'/(cid+'-vfx.png');raw=Image.open(source).convert('RGBA')
  for i,name in enumerate(['aura','wisp','sweep','burst']):
   box=(i%2*raw.width//2,i//2*raw.height//2,(i%2+1)*raw.width//2,(i//2+1)*raw.height//2)
   tile=raw.crop(box);rgb=np.asarray(tile).astype(np.float32)/255;alpha=rgb[:,:,:3].max(axis=2)*rgb[:,:,3]
   alpha[alpha<.025]=0
   clean=rgb[:,:,:3]/np.maximum(alpha[:,:,None],.001)
   result=Image.fromarray(np.uint8(np.clip(np.dstack([clean,alpha]),0,1)*255),'RGBA')
   result.thumbnail((768,768),Image.Resampling.LANCZOS);result.save(target/('fx-'+name+'.png'))
   records['effects'].append({'source':source.relative_to(ROOT).as_posix(),'crop':box,'output':'fx-'+name+'.png','sha256':hashlib.sha256(source.read_bytes()).hexdigest()})
  (OUT/'imports'/(cid+'-static.json')).write_text(json.dumps(records,indent=2),encoding='utf-8')
  print('Static assets',cid)
if __name__=='__main__':main()
