# coding: utf-8
"""Prepare courtyard detail references and preserve pre-polish evidence; offline."""
from pathlib import Path
import json, shutil
from PIL import Image,ImageDraw
from review_roster_scale import Atlas
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/courtyard-hd-v1'
REVIEW=ROOT/'artifacts/uppercut-polish'
def main():
 if (OUT/'jobs.json').exists():
  print('References and job manifest already registered; preserved without modification.');return
 for name in ['raw','records','references','prompts','imports']:(OUT/name).mkdir(parents=True,exist_ok=True)
 REVIEW.mkdir(parents=True,exist_ok=True)
 before=REVIEW/'before';before.mkdir(exist_ok=True)
 for source,name in [('art/stages/corps_courtyard/panorama.png','courtyard.png'),('output/imagegen/roster-v1/scale-calibration.json','scale-calibration.json')]:
  if not (before/name).exists():shutil.copy2(ROOT/source,before/name)
 atlas=Atlas(ROOT/'art/characters/nezuko')
 clips=['idle','body_stand_light','body_stand_heavy','crouch','guard_low','rising_kick']
 sheet=Image.new('RGB',(1440,240*len(clips)),'#18202e');draw=ImageDraw.Draw(sheet)
 for row,clip in enumerate(clips):
  folder=before/clip;folder.mkdir(exist_ok=True)
  frames=atlas.data['clips'][clip]['frames']
  for i in range(len(frames)):
   pose=atlas.frame(clip,i)
   if not (folder/f'{i}.png').exists():pose.save(folder/f'{i}.png')
   if i<6:
    pose=pose.crop((180,150,900,620)).resize((288,188),Image.Resampling.LANCZOS)
    sheet.paste(pose,(i*240-24,row*240+35),pose)
    draw.text((i*240+8,row*240+8),f'{clip} {i}',fill='white')
    draw.line((i*240,row*240+202,i*240+239,row*240+202),fill='#657386')
 sheet.save(before/'nezuko-contact.jpg',quality=96)
 atlas.close()
 source=Image.open(ROOT/'output/imagegen/fate-v1/raw/corps-courtyard.png').convert('RGB')
 height=round(source.width/4);top=(source.height-height)//2
 base=source.crop((0,top,source.width,top+height)).resize((6144,1536),Image.Resampling.LANCZOS)
 jobs=[]
 for row,y in enumerate([0,512]):
  for col,x in enumerate([0,1152,2304,3456,4608]):
   jid=f'courtyard-detail-{row}-{col}'
   ref=OUT/'references'/(jid+'.png');base.crop((x,y,x+1536,y+1024)).save(ref)
   prompt=OUT/'prompts'/(jid+'.txt')
   prompt.write_text("""Use case: stylized-concept. Asset: high-detail crop of a continuous anime fighting-game stage.
The supplied image is the EXACT composition and geometry reference. Repaint the same Demon Slayer Corps headquarters garden courtyard at bright morning light, with crisp ink contours and carefully resolved hand-painted anime detail.
Add actual small-scale detail: clear roof tiles, fine wood grain along existing veranda beams, separated gravel and stone edges, precise foliage leaves, softly defined wisteria blossoms. Retain the existing calm cream, dark wood, fresh green and pale violet palette.
Lock every roof line, vertical beam, garden bed, shadow, perspective line, ground level and all four crop boundaries at the exact reference position. Preserve existing empty fighting ground. Match the reference lighting and exposure.
No reframing, zoom, geometric changes, new objects, people, weapons, text, logos, vignette, haze or depth-of-field blur. Edge-to-edge sharp painted detail. Output only this complete 1536 by 1024 patch.
""",encoding='utf-8')
   jobs.append(dict(id=jid,group='stage-detail',prompt=prompt.relative_to(ROOT).as_posix(),out=(OUT/'raw'/(jid+'.png')).relative_to(ROOT).as_posix(),size='1536x1024',references=[ref.relative_to(ROOT).as_posix()],metadata=dict(stage='corps_courtyard',target_rect=[x,y,1536,1024])))
 (OUT/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2),encoding='utf-8')
 print('Saved pre-polish frames and 10 overlapping courtyard references; no API requests sent.')
if __name__=='__main__':main()
