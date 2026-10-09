"""Import the complete normal Nezuko guard redraw at one shared pixel scale."""
import importlib.util,json,hashlib
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from match_nezuko_guard_colors import match_colors
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/normal-guard-redraw-v3'
FOLDER=ROOT/'art/characters/nezuko'
SOURCE=OUT/'raw/normal-guard-dns-recovered.png'
BASE=ROOT/'output/imagegen/guard-fist-v1/baseline/normal'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 spec=importlib.util.spec_from_file_location('guard_key',ROOT/'tools/repair_nezuko_guard_fists.py');key=importlib.util.module_from_spec(spec);spec.loader.exec_module(key)
 image=Image.open(SOURCE).convert('RGB');assert image.size==(1536,1024)
 original=read(BASE/'clip.json');manifest=read(FOLDER/'atlas.json');page=Image.new('RGBA',(1024,512));entries=[];records=[]
 for i,old in enumerate(original['frames']):
  cell=image.crop((i%3*512,i//3*512,i%3*512+512,i//3*512+512))
  premult=key.unkey(cell);alpha=premult[:,:,3:4];rgb=premult[:,:,:3]/np.maximum(alpha,0.001)
  rgba=np.clip(np.rint(np.concatenate([rgb,alpha],axis=2)*255),0,255).astype('uint8');rgba[rgba[:,:,3]<8]=0
  # One shared 0.5 scale: no per-frame fit-to-box stretching or shrinking.
  frame=Image.fromarray(rgba).resize((256,256),Image.Resampling.LANCZOS)
  a=np.array(frame);a[a[:,:,3]<8]=0;frame=Image.fromarray(a);bbox=frame.getbbox();assert bbox
  frame=match_colors(frame.crop(bbox))
  offset=[old['offset'][0]+bbox[0]-12,old['offset'][1]+old['region'][3]-frame.height]
  x=i%4*256;y=i//4*256;assert frame.width<=256 and frame.height<=256
  page.paste(frame,(x,y));entries.append(dict(texture='guard-low-redraw.png',region=[x,y,*frame.size],offset=offset))
  (OUT/'frames').mkdir(exist_ok=True);frame.save(OUT/'frames'/f'{i}.png')
  records.append(dict(frame=i,source_cell=[i%3*512,i//3*512,512,512],scale=0.5,bounds=list(bbox),size=list(frame.size),offset=offset,feet_y=offset[1]+frame.height,original_size=old['region'][2:],original_feet_y=old['offset'][1]+old['region'][3],height_ratio=frame.height/old['region'][3],width_ratio=frame.width/old['region'][2],sha256=sha(OUT/'frames'/f'{i}.png')))
  assert 0.90<records[-1]['height_ratio']<1.10,records[-1]
 page.save(FOLDER/'guard-low-redraw.png');manifest['clips']['guard_low']['frames']=entries;save(FOLDER/'atlas.json',manifest)
 save(OUT/'import.json',dict(source=SOURCE.relative_to(ROOT).as_posix(),source_sha256=sha(SOURCE),shared_scale=0.5,color_correction="output/imagegen/guard-color-v4/record.json",frames=records))
 before=read(OUT/'baseline/atlas.json')
 assert {k:v for k,v in before.items() if k!='clips'}=={k:v for k,v in manifest.items() if k!='clips'}
 for name,clip in before['clips'].items():
  if name!='guard_low':assert clip==manifest['clips'][name],name
 assert {k:v for k,v in before['clips']['guard_low'].items() if k!='frames'}=={k:v for k,v in manifest['clips']['guard_low'].items() if k!='frames'}
 for path,digest in read(OUT/'baseline/awakening-hashes.json').items():assert sha(ROOT/path)==digest,'Awakening must stay untouched'
 preview=Image.new('RGB',(1440,590),'#293044');d=ImageDraw.Draw(preview);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',18)
 for i,e in enumerate(entries):
  for row in range(2):
   im=Image.open(BASE/f'{i}.png').convert('RGBA') if row==0 else Image.open(OUT/'frames'/f'{i}.png').convert('RGBA')
   old=original['frames'][i];ox=old['offset'][0] if row==0 else e['offset'][0]
   px=i*240+12+ox-old['offset'][0];py=row*295+272-im.height
   preview.paste(im,(px,py),im);d.text((i*240+12,row*295+8),('原蹲防' if row==0 else '完整重绘')+f' {i+1}',font=font,fill='white');d.line((i*240,row*295+272,i*240+239,row*295+272),fill='#58697d')
 preview.save(OUT/'preview.png')
 print(json.dumps(records,ensure_ascii=False,indent=2));print('Imported normal guard only; unchanged awakened hashes and clip timings.')
if __name__=='__main__':main()
