# coding: utf-8
"""Build the generated title and courtyard locally; never calls an image service."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/fate-v1'
def save(path,data):
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
def source(key):
 path=OUT/'raw'/(key+'.png')
 im=Image.open(path).convert('RGB')
 record=json.loads((OUT/'records'/(key+'.json')).read_text(encoding='utf-8-sig'))
 record.update(actual_size=list(im.size),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),accepted=True)
 save(OUT/'records'/(key+'.json'),record)
 return path,im,record
def main():
 path,poster,record=source('title-poster')
 target=ROOT/'art/ui/title-poster.png';target.parent.mkdir(parents=True,exist_ok=True)
 poster.save(target)
 save(OUT/'imports/title-poster.json',dict(source=path.relative_to(ROOT).as_posix(),actual_size=list(poster.size),crop=None,output=target.relative_to(ROOT).as_posix(),title='\u9b3c\u706d\u4e4b\u5203\uff1a\u5bbf\u547d\u5bf9\u51b3',sha256=record['sha256']))
 from build_menu_art import ready as menu_ready,build as build_menu
 if menu_ready():build_menu()
 from build_courtyard_hd import ready,build
 if ready():
  build();return
 path,scene,record=source('corps-courtyard')
 w=scene.width;h=round(w/4);top=(scene.height-h)//2
 panorama=scene.crop((0,top,w,top+h))
 target=ROOT/'art/stages/corps_courtyard';target.mkdir(parents=True,exist_ok=True)
 panorama.save(target/'panorama.png')
 tile_width=w//4;pad=8;padded=np.pad(np.array(panorama),((pad,pad),(pad,pad),(0,0)),mode='edge');tiles=[]
 for i in range(4):
  x=i*tile_width;tw=tile_width if i<3 else w-x;name=f'panorama-{i}.png'
  Image.fromarray(padded[:,x:x+tw+2*pad]).save(target/name)
  tiles.append(dict(texture=name,rect=[x,0,tw,h],region=[pad,pad,tw,h]))
 # Camera-sized central crop; rendering uses the full panorama.
 view_width=round(h*1280/792);left=(w-view_width)//2
 panorama.crop((left,0,left+view_width,h)).resize((960,594),Image.Resampling.LANCZOS).save(target/'thumbnail.jpg',quality=95)
 src=dict(path=path.relative_to(ROOT).as_posix(),actual_size=list(scene.size),crop=[0,top,w,top+h],sha256=record['sha256'])
 manifest=dict(revision='fate-v1',size=[w,h],render_size=[3168,792],world_width=960,layers=['panorama'],parallax=[1.0],tiles=tiles,sources=[src])
 save(target/'stage.json',manifest)
 save(OUT/'imports/corps-courtyard.json',dict(source=src,output_size=[w,h],resampled=False,gutter_pixels=pad,tiles=tiles))
 print('Title:',poster.size,'Courtyard:',panorama.size,'four lossless tiles; no generated pixels rescaled.')
if __name__=='__main__':main()
