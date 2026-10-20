"""Magnified leg-motion comparison and calf silhouette checks."""
import json
from pathlib import Path

import numpy as np
from PIL import Image,ImageDraw,ImageFont

ANIM=Path(__file__).resolve().parent
FONT='C:/Windows/Fonts/msyh.ttc'
REGION=(375,938,945,1498)


def main(previous_frames=None):
    if previous_frames is None:
        from build_animation import Animator,read
        rig=read(ANIM/'rig.json')
        key=np.asarray(Image.open(ANIM/'idle-key.png').convert('RGBA'))
        animator=Animator(key,rig)
        previous_frames=[Image.fromarray(animator.frame(i/rig['frames'],stabilize_legs=False)[0]) for i in range(rig['frames'])]
    (ANIM/'review').mkdir(exist_ok=True)
    frames=[]
    old_images=[]
    new_images=[]
    for index in range(12):
        a=previous_frames[index]
        b=Image.open(ANIM/'frames'/f'frame-{index:02d}.png').convert('RGBA')
        old_images.append(a)
        new_images.append(b)
        board=Image.new('RGBA',(1200,720),'#eee9e3')
        draw=ImageDraw.Draw(board)
        draw.text((28,20),'膝盖和小腿 · 修改前后对照',font=ImageFont.truetype(FONT,28),fill='#372c30')
        for side,(im,label) in enumerate([(a,'上一版'),(b,'修订版 · 腿部更稳定')]):
            x=15+side*600
            draw.rounded_rectangle((x,80,x+570,695),radius=12,fill='#e3ddd7')
            board.alpha_composite(im.crop(REGION),(x,122))
            draw.text((x+16,89),label,font=ImageFont.truetype(FONT,23),fill='#5c4d56')
        frames.append(board.convert('RGB'))
    frames[0].save(ANIM/'review/lower-leg-comparison.webp',save_all=True,append_images=frames[1:],duration=100,loop=0,lossless=True)
    detail=Image.new('RGB',(1200,1440),'#eee9e3')
    detail.paste(frames[3],(0,0))
    detail.paste(frames[9],(0,720))
    detail.save(ANIM/'review/lower-leg-extremes.png')
    rows=[]
    for y in [1220,1250,1300,1350]:
        for name,left,right in [('back',340,530),('front',650,810)]:
            widths={}
            for version,images in [('v1',old_images),('v2',new_images)]:
                values=[]
                for im in images:
                    alpha=np.asarray(im)[y+48,left+55:right+55,3]
                    xs=np.where(alpha>128)[0]
                    values.append(int(xs[-1]-xs[0]+1))
                widths[version]=dict(widths=values,range=max(values)-min(values))
            rows.append(dict(leg=name,source_y=y,**widths))
    result=dict(method='Alpha silhouette widths at calf-wrap cross-sections in original-source coordinates; one canvas and fixed windows for all frames.',rows=rows)
    (ANIM/'calf-width-check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'calf_width_ranges': [{'leg':r['leg'],'y':r['source_y'],'before':r['v1']['range'],'after':r['v2']['range']} for r in rows]},indent=2))


if __name__=='__main__':
    main()
