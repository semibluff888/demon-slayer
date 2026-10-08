"""Build delivery previews from real Godot captures, without altering character art."""
import json,math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path.cwd();OUT=ROOT/'artifacts/awakening-v7'
report=json.loads((OUT/'captures.json').read_text(encoding='utf-8-sig'))
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',19)
labels={'idle':'待机','walk':'行走','walk_back':'后退','dash_forward':'前冲刺','dash_back':'后冲刺','crouch':'下蹲','stand':'站起','jump':'跳跃','stand_light':'轻攻击','stand_heavy':'重攻击','blood_kick':'爆血踢','max':'MAX 超杀'}
frames=[]
for row in report['motion_trace']:
    with Image.open(OUT/('motion-%03d.png'%row['sample'])) as src:im=src.convert('RGB').resize((960,540),Image.Resampling.LANCZOS)
    d=ImageDraw.Draw(im);d.rounded_rectangle((16,474,290,510),6,fill='#141e2b');d.text((27,480),labels.get(row['label'],row['label'])+' · 实机输入',font=font,fill='#f2dfc1');frames.append(im)
frames[0].save(OUT/'motion-preview.gif',save_all=True,append_images=frames[1:],duration=50,loop=0,optimize=False)
# Each tile retains exactly the same screenshot crop and scale.
selected=[('待机',0),('行走',9),('冲刺',22),('下蹲',36),('重攻击',74),('爆血踢',90)]
sheet=Image.new('RGB',(1560,720),'#15202f');draw=ImageDraw.Draw(sheet)
for index,(title,sample) in enumerate(selected):
    im=Image.open(OUT/('motion-%03d.png'%sample)).convert('RGB').crop((0,295,520,615));x=(index%3)*520;y=(index//3)*360
    sheet.paste(im,(x,y+36));draw.text((x+18,y+8),title,font=font,fill='#f2dfc1')
sheet.save(OUT/'motion-overview.jpg',quality=95)
# Gallery keeps the same physical crop and covers first/middle/last in every clip.
clips=json.loads((ROOT/'art/characters/nezuko/awakening/atlas.json').read_text(encoding='utf-8-sig'))['clips']
tiles=[]
for clip,meta in clips.items():
    if clip in ['victory','round_intro','round_victory','round_defeat']:continue
    for frame in [0,len(meta['frames'])//2,len(meta['frames'])-1]:
        path=OUT/('nezuko-%s-%02d.png'%(clip,frame))
        if not path.exists():continue
        im=Image.open(path).convert('RGB').crop((0,290,680,625)).resize((544,268),Image.Resampling.LANCZOS)
        tile=Image.new('RGB',(544,295),'#15202f');tile.paste(im,(0,27));ImageDraw.Draw(tile).text((10,3),clip+' / '+str(frame),font=font,fill='#f2dfc1');tiles.append(tile)
for page in range(math.ceil(len(tiles)/24)):
    chosen=tiles[page*24:(page+1)*24];canvas=Image.new('RGB',(4*544,math.ceil(len(chosen)/4)*295),'#15202f')
    for i,tile in enumerate(chosen):canvas.paste(tile,((i%4)*544,(i//4)*295))
    canvas.save(OUT/('runtime-gallery-%02d.jpg'%page),quality=93)
print('Preview:',len(frames),'real-input samples;',len(tiles),'gallery frames')
