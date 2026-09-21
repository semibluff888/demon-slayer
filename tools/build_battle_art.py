"""Offline import of battle-v5 art, with native detail and source provenance."""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/battle-v5'
RESAMPLE=getattr(Image,'Resampling',Image).LANCZOS

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def save_json(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def matte(image,magenta=False):
    if magenta and image.mode=='RGBA' and image.getchannel('A').getextrema()[0]<255:
        return image.copy()
    rgb=np.array(image.convert('RGB'),dtype=np.float32)/255
    if magenta:
        key=np.minimum(rgb[:,:,0],rgb[:,:,2])-rgb[:,:,1]
        alpha=np.clip(1-(key-48/255)*3.5,0,1)
        clean=(rgb-np.array([1,0,1],dtype=np.float32)*(1-alpha[:,:,None]))/np.maximum(alpha[:,:,None],1/255)
    else:
        alpha=np.max(rgb,axis=2)
        alpha=np.where(alpha<0.016,0,alpha)
        clean=rgb/np.maximum(alpha[:,:,None],1/255)
    rgba=np.dstack((np.clip(clean,0,1),alpha))
    return Image.fromarray(np.uint8(np.clip(rgba*255,0,255)),'RGBA')

def assets():
    for cid in ('tanjiro','zenitsu'):
        path=OUT/'raw'/(cid+'-battle-portrait.png')
        if not path.exists():continue
        im=matte(Image.open(path),True)
        box=im.getbbox()
        if not box:raise ValueError('Empty portrait '+cid)
        im=im.crop(box)
        im.thumbnail((976,1000),RESAMPLE)
        canvas=Image.new('RGBA',(1024,1024))
        canvas.alpha_composite(im,((1024-im.width)//2,1024-im.height))
        target=ROOT/'art/characters'/cid
        canvas.save(target/'battle-portrait.png')
        # Keep the established thumbnail interface while using the new identity source.
        thumbnail=canvas.crop((32,0,992,960)).resize((192,192),RESAMPLE)
        bg=Image.new('RGBA',(192,192),'#173543' if cid=='tanjiro' else '#403326')
        bg.alpha_composite(thumbnail)
        bg.save(target/'avatar.png')
        print('Imported portrait',cid,Image.open(path).size)
    for key in ('water-dragon','sun-flame-arc'):
        path=OUT/'raw'/(key+'.png')
        if path.exists():
            im=Image.open(path).convert('RGB')
            im.save(ROOT/'art/effects'/(key+'.png'))
    for key in ('water-slash','water-wheel','thunder','water-dragon','sun-flame-arc'):
        path=ROOT/'art/effects'/(key+'.png')
        if path.exists():
            matte(Image.open(path)).save(ROOT/'art/effects'/(key+'-body.png'))
    print('Element bodies imported with unpremultiplied alpha; glow originals retained.')

def stage():
    import cv2
    jobs=json.loads((OUT/'jobs.json').read_text(encoding='utf-8-sig'))
    jobs=[j for j in jobs if j['metadata']['kind']=='stage']
    missing=[j['id'] for j in jobs if not (ROOT/j['out']).exists()]
    if missing:raise ValueError('Stage sources incomplete: '+', '.join(missing))
    total=np.zeros((2400,9600,3),np.float32)
    weights=np.zeros((2400,9600),np.float32)
    sources=[]
    for job in jobs:
        x,y,w,h=job['metadata']['rect']
        source=ROOT/job['out']
        im=Image.open(source).convert('RGB')
        actual=im.size
        if im.width<w or im.height<h:
            raise ValueError(f'{job["id"]}: actual {actual} below required {w}x{h}; cannot claim native 4K detail.')
        if im.size!=(w,h):
            im=im.resize((w,h),RESAMPLE)
        generated=np.array(im)
        reference=np.array(Image.open(ROOT/job['references'][0]).convert('RGB'))
        # Register small model drift to the original continuous layout.
        warp=np.eye(2,3,dtype=np.float32)
        score=None
        try:
            ref=cv2.resize(cv2.cvtColor(reference,cv2.COLOR_RGB2GRAY),(w//2,h//2)).astype(np.float32)/255
            gen=cv2.resize(cv2.cvtColor(generated,cv2.COLOR_RGB2GRAY),(w//2,h//2)).astype(np.float32)/255
            score,warp=cv2.findTransformECC(ref,gen,warp,cv2.MOTION_AFFINE,(cv2.TERM_CRITERIA_EPS|cv2.TERM_CRITERIA_COUNT,80,0.0001))
            if abs(warp[0,0]-1)>0.045 or abs(warp[1,1]-1)>0.045 or abs(warp[0,1])>0.04 or abs(warp[1,0])>0.04:
                warp=np.eye(2,3,dtype=np.float32)
            warp[:,2]*=2
            generated=cv2.warpAffine(generated,warp,(w,h),flags=cv2.INTER_LINEAR|cv2.WARP_INVERSE_MAP,borderMode=cv2.BORDER_REFLECT_101)
        except cv2.error:
            warp=np.eye(2,3,dtype=np.float32)
        # Preserve coherent low-frequency night lighting across all independent crops.
        data=generated.astype(np.float32)
        low=cv2.GaussianBlur(data,(0,0),24)
        target_low=cv2.GaussianBlur(reference.astype(np.float32),(0,0),24)
        data=np.clip(data+target_low-low,0,255)
        wx=np.ones(w,np.float32);wy=np.ones(h,np.float32)
        if x>0:wx[:192]=np.linspace(0,1,192)
        if x+w<9600:wx[-192:]=np.linspace(1,0,192)
        if y>0:wy[:336]=np.linspace(0,1,336)
        if y+h<2400:wy[-336:]=np.linspace(1,0,336)
        weight=wy[:,None]*wx[None,:]
        total[y:y+h,x:x+w]+=data*weight[:,:,None]
        weights[y:y+h,x:x+w]+=weight
        sources.append(dict(path=job['out'].replace('\\','/'),sha256=digest(source),actual_size=list(actual),target_rect=[x,y,w,h],registration=warp.tolist(),correlation=float(score) if score is not None else None))
        print('Composited',job['id'],'native',actual,flush=True)
    if np.any(weights<=0):raise ValueError('Uncovered stage pixels')
    pixels=np.uint8(np.clip(total/weights[:,:,None],0,255))
    target=ROOT/'art/stages/wisteria'
    master=Image.fromarray(pixels,'RGB')
    master.save(target/'panorama.png')
    padded=np.pad(pixels,((8,8),(8,8),(0,0)),mode='edge')
    tiles=[]
    for col in range(4):
        filename=f'panorama-{col}.png'
        Image.fromarray(padded[:,col*2400:col*2400+2416],'RGB').save(target/filename)
        tiles.append(dict(texture=filename,rect=[col*2400,0,2400,2400],region=[8,8,2400,2400]))
    master.crop((2666,0,6933,2400)).resize((2048,1152),RESAMPLE).save(target/'menu.jpg',quality=95)
    save_json(target/'stage.json',dict(revision='battle-v5',size=[9600,2400],world_width=960,render_size=[3168,792],
        layers=['panorama'],parallax=[1.0],tiles=tiles,sources=sources,
        detail_strategy='21 native-resolution registered detail repaints; original composition used only for geometry and low-frequency illumination. No source upscaling.',
        composition='One continuous painting and shared world transform; moon, reflection, architecture and floor stay registered.'))
    print('Built 9600x2400 detail panorama, four 2416px runtime textures.')

def manifest():
    files=[]
    for folder in ('art/effects','art/characters/tanjiro','art/characters/zenitsu','art/stages/wisteria'):
        for p in (ROOT/folder).glob('*.png'):
            if 'atlas-' in p.name:continue
            im=Image.open(p)
            files.append(dict(path=str(p.relative_to(ROOT)).replace('\\','/'),size=list(im.size),mode=im.mode,sha256=digest(p)))
    records=[]
    for p in sorted((OUT/'records').glob('*.json')):
        records.append(json.loads(p.read_text(encoding='utf-8-sig')))
    save_json(OUT/'manifest.json',dict(revision='battle-v5',route='CPA / gpt-image-2',records=records,inventory=files,
        rebuild='python tools/build_battle_art.py --part all',billing='Unknown costs remain null.'))
if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--part',choices=['assets','stage','manifest','all'],default='all')
    part=parser.parse_args().part
    if part in ('assets','all'):assets()
    if part in ('stage','all'):stage()
    manifest()

