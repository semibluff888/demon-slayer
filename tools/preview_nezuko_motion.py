"""Build compact, labelled previews from actual Godot motion captures."""
import argparse,json,subprocess
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
FONT='C:/Windows/Fonts/msyh.ttc'
LABELS={'idle':'已认可的待机','walk':'向前行走','walk_back':'向后行走','dash_forward':'前冲','dash_back':'后撤','air_light':'空中轻爪','air_heavy':'空中重爪','body_air_light':'空中轻踢','body_air_heavy':'空中重踢','blood_kick':'爆血飞踢','rising_kick':'升空踢','spinning_kick':'回旋踢','blood_burst':'血鬼术·爆血','awakened_combo':'已认可的 MAX'}
def main():
 p=argparse.ArgumentParser();p.add_argument('--source-dir',default='artifacts/awakening-v8');p.add_argument('--ffmpeg',required=True);args=p.parse_args()
 out=ROOT/args.source_dir;capture=json.loads((out/'captures.json').read_text(encoding='utf-8'))
 font=ImageFont.truetype(FONT,23);small=ImageFont.truetype(FONT,19)
 picks=[('idle',0),('walk',3),('walk_back',3),('dash_forward',3),('dash_back',3),('air_light',3),('air_heavy',3),('body_air_heavy',3),('blood_kick',4),('rising_kick',4),('spinning_kick',6),('blood_burst',6)]
 overview=Image.new('RGB',(1600,1074),'#111b2c');draw=ImageDraw.Draw(overview)
 draw.text((24,16),'祢豆子 · 觉醒动作尺寸修订',font=ImageFont.truetype(FONT,30),fill='#f2dfcc')
 draw.text((24,61),'游戏内实机画面 / 所有格子采用相同裁切比例',font=small,fill='#9bb2ca')
 for i,(clip,frame) in enumerate(picks):
  with Image.open(out/('nezuko-%s-%02d.png'%(clip,frame))) as im:tile=im.convert('RGB').crop((385,295,835,635)).resize((400,302),Image.Resampling.LANCZOS)
  x=(i%4)*400;y=110+(i//4)*321
  overview.paste(tile,(x,y));draw.rectangle((x,y,x+400,y+32),fill='#172338');draw.text((x+12,y+2),LABELS[clip],font=small,fill='#ffe3db')
 overview.save(out/'motion-overview.jpg',quality=94)
 # Every frame is a captured game render; no generative video or synthetic tweening.
 rows=[r for r in capture['motion_trace'] if r['label'] in LABELS]
 command=[args.ffmpeg,'-y','-loglevel','error','-f','rawvideo','-pixel_format','rgb24','-video_size','1280x720','-framerate','20','-i','pipe:0','-an','-c:v','libx264','-preset','medium','-crf','22','-pix_fmt','yuv420p','-movflags','+faststart',str(out/'motion-preview.mp4')]
 process=subprocess.Popen(command,stdin=subprocess.PIPE)
 for row in rows:
  with Image.open(out/('motion-%04d.png'%row['sample'])) as source:frame=source.convert('RGB')
  d=ImageDraw.Draw(frame);label=LABELS[row['label']]+'  /  '+('朝右' if row['facing']>0 else '朝左')
  d.rounded_rectangle((455,154,825,203),radius=8,fill='#142033');d.text((473,163),label,font=font,fill='#f5d9df')
  process.stdin.write(frame.tobytes())
 process.stdin.close()
 if process.wait()!=0:raise RuntimeError('ffmpeg preview encode failed')
 # Eighteen consecutive poses include two loop seams; camera/world translation is retained.
 walk=[r for r in capture['motion_trace'] if r['label']=='walk' and r['facing']==1][:18]
 seam=Image.new('RGB',(1280,6*210),'#152034');d=ImageDraw.Draw(seam)
 for i,row in enumerate(walk):
  with Image.open(out/('motion-%04d.png'%row['sample'])) as im:tile=im.convert('RGB').crop((0,310,700,620)).resize((426,189),Image.Resampling.LANCZOS)
  x=i%3*426;y=i//3*210;seam.paste(tile,(x,y+21));d.text((x+8,y),'tick %d / pose %d / x %.2f'%(row['tick'],row['frame'],row['x']),font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',16),fill='white')
 seam.save(out/'walk-cycle-contact-sheet.jpg',quality=93)
 (out/'preview.json').write_text(json.dumps({'source':'Actual Godot captures through combat inputs','fps':20,'samples':len(rows),'duration_seconds':len(rows)/20,'video':'motion-preview.mp4','overview':'motion-overview.jpg','walk_contact_sheet':'walk-cycle-contact-sheet.jpg'},indent=2),encoding='utf-8')
 print('Preview:',len(rows),'samples,',len(rows)/20,'seconds')
if __name__=='__main__':main()
