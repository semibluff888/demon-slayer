"""Visual acceptance at a shared ruler, including before/after animation playback."""
import argparse,html,json,math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/awakening-v7/review'
VIEW=(96,48,928,640);SIZE=(416,296);FONT=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',17)
def load(directory):
 manifest=json.loads((directory/'atlas.json').read_text(encoding='utf-8-sig'));pages={};clips={}
 for clip,meta in manifest['clips'].items():
  frames=[]
  for entry in meta['frames']:
   if entry['texture'] not in pages:
    with Image.open(directory/entry['texture']) as im:pages[entry['texture']]=im.convert('RGBA')
   x,y,w,h=entry['region'];frame=Image.new('RGBA',tuple(manifest['canvas_size']));frame.alpha_composite(pages[entry['texture']].crop((x,y,x+w,y+h)),tuple(entry['offset']));frames.append(frame)
  clips[clip]=frames
 return manifest,clips

def tile(im,label):
 canvas=Image.new('RGB',(416,326),'#182438');d=ImageDraw.Draw(canvas);thumb=im.crop(VIEW).resize(SIZE,Image.Resampling.LANCZOS);canvas.paste(thumb,(0,28),thumb)
 d.line((0,288,415,288),fill='#667790');d.text((9,5),label,font=FONT,fill='#e3d5bb');return canvas

def main():
 global OUT
 p=argparse.ArgumentParser();p.add_argument('--clip');p.add_argument('--source-dir',default='output/imagegen/awakening-v7');args=p.parse_args();OUT=ROOT/args.source_dir/'review';OUT.mkdir(parents=True,exist_ok=True)
 manifest,clips=load(ROOT/'art/characters/nezuko/awakening');_,old=load(OUT.parent/'baseline');rows=[];htmls=[]
 for clip,frames in clips.items():
  if clip in ['round_intro','round_victory','round_defeat','victory'] or (args.clip and clip!=args.clip):continue
  sheet=Image.new('RGB',(4*416,math.ceil(len(frames)/3)*326),'#182438')
  for start in range(0,len(frames),3):
   y=(start//3)*326;sheet.paste(tile(clips['idle'][0],'APPROVED IDLE (same ruler)'),(0,y))
   for i in range(start,min(start+3,len(frames))):sheet.paste(tile(frames[i],clip+' / '+str(i)),((i%3+1)*416,y))
  name='fixed-'+clip+'.jpg';sheet.save(OUT/name,quality=94)
  htmls.append('<details><summary>'+html.escape(clip)+'</summary><img src="'+name+'"></details>')
  i=len(frames)//2;rows.append([tile(clips['idle'][0],'APPROVED IDLE'),tile(old[clip][i],clip+' / BEFORE'),tile(frames[i],clip+' / AFTER')])
 for page in range(math.ceil(len(rows)/8)):
  picked=rows[page*8:(page+1)*8];sheet=Image.new('RGB',(3*416,len(picked)*326),'#182438')
  for y,row in enumerate(picked):
   for x,im in enumerate(row):sheet.paste(im,(x*416,y*326))
  sheet.save(OUT/('comparison-%02d.jpg'%page),quality=93)
 sequence=[]
 for clip in ['idle','walk','walk_back','dash_forward','crouch','jump','stand_heavy','blood_kick','awakened_combo','idle']:
  for i,frame in enumerate(clips[clip]):
   out=Image.new('RGB',(832,326),'#182438');out.paste(tile(clips['idle'][0],'APPROVED IDLE'),(0,0));out.paste(tile(frame,clip+' / '+str(i)),(416,0));sequence.append(out)
 sequence[0].save(OUT/'motion-ruler.gif',save_all=True,append_images=sequence[1:],duration=110,loop=0,optimize=False)
 (OUT/'fixed-ruler.html').write_text('<!doctype html><meta charset="utf-8"><title>Nezuko motion proportions</title><style>body{background:#121c2d;color:#eddfca;font:17px sans-serif}img{max-width:100%}summary{padding:15px}</style><h1>Shared physical ruler</h1><p>Idle is repeated at the identical pixel scale in every row. No silhouette-fit thumbnails.</p><img src="motion-ruler.gif">'+''.join(htmls),encoding='utf-8')
 print('Fixed-ruler review:',len(rows),'clips')
if __name__=='__main__':main()
