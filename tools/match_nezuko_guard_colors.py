"""Small material-aware RGB corrections to match normal Nezuko's crouch palette."""
from pathlib import Path
import json,hashlib
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/guard-color-v4'
FOLDER=ROOT/'art/characters/nezuko'
# RGB deltas from crouch frames 4/5: muted brown coat, cream skin, softer orange.
DELTAS={'coat':[-7,2,4],'skin':[-1,1,4],'orange':[-12,2,14]}
def ramp(x,a,b):
 t=np.clip((x-a)/(b-a),0,1);return t*t*(3-2*t)
def match_colors(image):
 a=np.array(image.convert('RGBA'));v=a[:,:,:3].astype(float);r,g,b=v.transpose(2,0,1)
 coat=ramp(r,35,60)*(1-ramp(r,115,155))*ramp(r-g,10,24)*(1-ramp(r-g,48,70))*(1-ramp(abs(g-b),16,30))
 skin=ramp(r,215,240)*ramp(g,175,205)*ramp(b,140,175)*ramp(r-g,6,16)*(1-ramp(r-g,38,52))*ramp(g-b,5,13)*(1-ramp(g-b,32,45))
 orange=ramp(r,145,200)*ramp(r-g,55,85)*ramp(g-b,25,45)
 delta=coat[:,:,None]*DELTAS['coat']+skin[:,:,None]*DELTAS['skin']+orange[:,:,None]*DELTAS['orange']
 corrected=np.clip(np.rint(v+delta),0,255).astype('uint8');opaque=a[:,:,3]>0;a[opaque,:3]=corrected[opaque]
 return Image.fromarray(a)
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 OUT.mkdir(parents=True,exist_ok=True);(OUT/'.gdignore').write_text('');texture=FOLDER/'guard-low-redraw.png';baseline=OUT/'before.png'
 if not baseline.exists():baseline.write_bytes(texture.read_bytes())
 manifest_path=FOLDER/'atlas.json';manifest_bytes=manifest_path.read_bytes();m=read(manifest_path)
 awakening=FOLDER/'awakening/guard-fist.png';awakening_hash=sha(awakening)
 before=Image.open(baseline).convert('RGBA');after=match_colors(before)
 assert np.array_equal(np.array(before)[:,:,3],np.array(after)[:,:,3]);assert before.size==after.size
 after.save(texture);assert manifest_path.read_bytes()==manifest_bytes;assert sha(awakening)==awakening_hash
 source_out=ROOT/'output/imagegen/normal-guard-redraw-v3';registration=read(source_out/'import.json')
 for i,e in enumerate(m['clips']['guard_low']['frames']):
  x,y,w,h=e['region'];p=source_out/'frames'/f'{i}.png';after.crop((x,y,x+w,y+h)).save(p);registration['frames'][i]['sha256']=sha(p)
 registration['color_correction']='output/imagegen/guard-color-v4/record.json';save(source_out/'import.json',registration)
 save(OUT/'record.json',dict(reference_clip='crouch',reference_frames=[4,5],deltas=DELTAS,baseline_sha256=sha(baseline),result_sha256=sha(texture),alpha_unchanged=True,manifest_unchanged=True,awakening_unchanged=True,changed_pixels=int(np.any(np.array(before)!=np.array(after),axis=2).sum())))
 preview=Image.new('RGB',(1050,370),'#303846');d=ImageDraw.Draw(preview);font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',20)
 for col,label in enumerate(['蹲下参考','蹲防调整前','蹲防调整后']):
  e=m['clips']['crouch' if col==0 else 'guard_low']['frames'][5];x,y,w,h=e['region']
  page=Image.open(FOLDER/e['texture']).convert('RGBA') if col==0 else [before,after][col-1]
  im=page.crop((x,y,x+w,y+h));im=im.resize((round(w*1.2),round(h*1.2)),Image.Resampling.NEAREST)
  preview.paste(im,(col*350+8,350-im.height),im);d.text((col*350+15,12),label,font=font,fill='white')
 preview.save(OUT/'preview.png');print('Color-only correction applied to 6 normal guard frames. Alpha, dimensions, manifest and awakening unchanged.')
if __name__=='__main__':main()
