import json
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/motion-fixes-v1'
def sheet(cid,form,clips,suffix='before'):
 d=ROOT/'art/characters'/cid/form;m=json.loads((d/'atlas.json').read_text(encoding='utf-8-sig'));cache={}
 result=Image.new('RGB',(3072,230*len(clips)),'#202638');draw=ImageDraw.Draw(result)
 for row,clip in enumerate(clips):
  for i,e in enumerate(m['clips'][clip]['frames']):
   p=d/e['texture']
   if p not in cache:cache[p]=Image.open(p).convert('RGBA')
   x,y,w,h=e['region'];s=cache[p].crop((x,y,x+w,y+h));c=Image.new('RGBA',tuple(m['canvas_size']));c.alpha_composite(s,tuple(e['offset']))
   tile=c.crop((128,80,896,640)).resize((256,187),Image.Resampling.LANCZOS);px=i*256;py=row*230
   result.paste(tile,(px,py+25),tile);draw.text((px+5,py+5),f'{clip} {i} ({w}x{h})',fill='white')
 OUT.mkdir(parents=True,exist_ok=True);result.save(OUT/f'{cid}-{form or "normal"}-{suffix}.jpg',quality=95)
if __name__=='__main__':
 sheet('nezuko','awakening',['idle','blood_kick','spinning_kick','blood_burst','throw_forward','throw_success'])
 sheet('nezuko','',['idle','blood_burst','throw_forward','throw_success'])
 sheet('akaza','',['idle','throw_forward','throw_success'])
 sheet('zenitsu','',['idle','throw_forward','throw_success'])
