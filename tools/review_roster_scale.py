"""Fixed-scale anatomy review from the actual packed textures (offline)."""
import argparse, html, json, math
from pathlib import Path
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts/scale-fix'
class Atlas:
 def __init__(self,directory):
  self.directory=directory;self.data=json.loads((directory/'atlas.json').read_text(encoding='utf-8-sig'));self.pages={}
 def frame(self,clip,index):
  entry=self.data['clips'][clip]['frames'][index];name=entry['texture']
  if name not in self.pages:
   with Image.open(self.directory/name) as im:self.pages[name]=im.convert('RGBA')
  x,y,w,h=entry['region'];canvas=Image.new('RGBA',tuple(self.data['canvas_size']))
  canvas.alpha_composite(self.pages[name].crop((x,y,x+w,y+h)),tuple(entry['offset']))
  return canvas
 def close(self):
  for page in self.pages.values():page.close()
def paint(canvas,atlas,clip,index,x,y,scale=.5):
 # Uniform display scale and fixed shared feet/pelvis anchor. Never thumbnail a bbox.
 pose=atlas.frame(clip,index);pose=pose.resize((round(pose.width*scale),round(pose.height*scale)),Image.Resampling.LANCZOS)
 px=round(x-atlas.data['feet_anchor'][0]*scale);py=round(y-atlas.data['feet_anchor'][1]*scale)
 canvas.paste(pose,(px,py),pose)
def main():
 OUT.mkdir(exist_ok=True)
 jobs=json.loads((ROOT/'output/imagegen/roster-v1/jobs.json').read_text(encoding='utf-8-sig'))
 chars=sorted({j['metadata']['character'] for j in jobs if j['group']=='animation'})
 sections=[]
 for cid in chars:
  after=Atlas(ROOT/'art/characters'/cid);before=Atlas(OUT/'before'/cid)
  directory=OUT/cid;directory.mkdir(exist_ok=True)
  names=list(after.data['clips'])
  for group in range(math.ceil(len(names)/14)):
   sheet=Image.new('RGB',(1680,1260),'#101c2c');draw=ImageDraw.Draw(sheet)
   for k,name in enumerate(names[group*14:(group+1)*14]):
    x=(k%7)*240;y=(k//7)*630
    for row,ix in enumerate([0,len(after.data['clips'][name]['frames'])//2,len(after.data['clips'][name]['frames'])-1]):
     pose=after.frame(name,ix).crop((150,120,930,620)).resize((234,150))
     sheet.paste(pose,(x,y+row*200+25),pose)
     draw.line((x,y+row*200+159,x+239,y+row*200+159),fill='#59606c')
     draw.text((x+3,y+row*200+6),name+' '+str(ix),fill='white')
   sheet.save(OUT/(cid+'-after-'+str(group)+'.jpg'),quality=96)
  cards=[]
  for clip in names:
   count=len(after.data['clips'][clip]['frames']);rows=math.ceil(count/6)
   # Each chronological row is displayed before then after, with unchanged idle at left.
   sheet=Image.new('RGB',(1680,rows*640),'#101c2c');d=ImageDraw.Draw(sheet)
   for row in range(rows):
    for version,atlas in enumerate([before,after]):
     y=row*640+version*320;ground=y+280
     d.text((8,y+6),('BEFORE' if version==0 else 'AFTER')+' / '+clip,fill='#d6bf95')
     paint(sheet,after,'idle',0,90,ground,.5)
     d.text((8,y+304),'idle reference',fill='#7bafc1')
     for column in range(6):
      ix=row*6+column
      if ix>=count:break
      paint(sheet,atlas,clip,ix,340+column*240,ground,.5)
      d.text((242+column*240,y+304),'frame '+str(ix),fill='#a2bbce')
     d.line((0,ground+1,1680,ground+1),fill='#3d6976')
   filename=clip+'.jpg';sheet.save(directory/filename,quality=96)
   cards.append('<details><summary>'+html.escape(clip)+'</summary><img loading="lazy" src="'+cid+'/'+filename+'"></details>')
  selected=['guard_low','crouch_light','body_crouch_light','air_heavy','roll_forward','thrown_forward']
  selected+=['air_type','disorder','annihilation','blue_afterglow'] if cid=='akaza' else ['blood_kick','spinning_kick','blood_burst','awakened_combo']
  comparison=Image.new('RGB',(1500,1800),'#101c2c');d=ImageDraw.Draw(comparison)
  for k,clip in enumerate(selected):
   x=(k%5)*300;y=(k//5)*900;count=len(after.data['clips'][clip]['frames'])
   ix=count-1 if clip=='thrown_forward' else (0 if clip=='guard_low' else count//2)
   for row,(label,atlas,name,frame) in enumerate([('IDLE',after,'idle',0),('BEFORE',before,clip,ix),('AFTER',after,clip,ix)]):
    ground=y+row*300+264
    paint(comparison,atlas,name,frame,x+133,ground,.5)
    d.line((x,ground+1,x+299,ground+1),fill='#3d6976')
    d.text((x+7,y+row*300+9),clip+' / '+label,fill='#d6bf95')
  comparison.save(OUT/(cid+'-comparison.jpg'),quality=96)
  sections.append('<h2>'+cid+'</h2><img src="'+cid+'-comparison.jpg">'+''.join(cards))
  before.close();after.close()
 page="""<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>角色体型修复核对</title><style>body{margin:32px auto;max-width:1680px;background:#101c2c;color:#e9dfc8;font:16px/1.7 system-ui;padding:0 20px}img,video{width:100%;display:block}details{border:1px solid #3d6976;margin:12px 0}summary{padding:12px;cursor:pointer}a{color:#8ad5e5}</style><h1>角色体型修复核对</h1><p>同一图集绘制比例、同一锚点。IDLE 为未改动的待机标尺，BEFORE 为修复前，AFTER 为修复后。下方可展开两位角色全部动作的逐帧对照。</p><p>蹲姿保留真实高度变化；旋转姿势按骨盆对齐；受投末段贴地。对照图从实际打包图集取帧，没有为每个姿势单独适配显示大小。</p><p><a href="../../docs/roster-scale-fix.md">修复与复现说明</a> · <a href="engine/index.html">引擎动作检查</a></p>"""
 page+=''.join(sections)
 (OUT/'index.html').write_text(page,encoding='utf-8')
 print('Fixed-scale review:',OUT/'index.html')
if __name__=='__main__':main()
