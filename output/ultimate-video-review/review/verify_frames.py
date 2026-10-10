import json
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from inspect_video import ROOT, FFMPEG
manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8'))
font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
small=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
canvas=Image.new('RGB',(1280,len(manifest['clips'])*225),'#151922')
draw=ImageDraw.Draw(canvas)
for row,c in enumerate(manifest['clips']):
    path=ROOT/c['file']
    d=c['duration_seconds']
    draw.text((8,row*225+3),c['title'],font=font,fill='white')
    for col,t in enumerate([0,d*.33,d*.67,d-1/60]):
        r=subprocess.run([FFMPEG,'-v','error','-ss',str(t),'-i',str(path),'-frames:v','1','-vf','scale=320:180','-f','rawvideo','-pix_fmt','rgb24','pipe:1'],capture_output=True,check=True)
        assert len(r.stdout)==320*180*3
        canvas.paste(Image.frombytes('RGB',(320,180),r.stdout),(col*320,row*225+30))
        draw.text((col*320+5,row*225+207),f'{t:.3f}s',font=small,fill='#b8c8df')
canvas.save(ROOT/'review/final_clips_check.jpg',quality=90)
print('Verified first / middle / last decoded frames for all 8 clips.')
