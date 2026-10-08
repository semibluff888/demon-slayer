"""Prepare v7 using the approved GAME idle, never the ordinary-form anatomy."""
import copy, hashlib, json, shutil, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_awakening_art import cyan_matte, clean
from build_roster_art import components
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/awakening-v7'
PREVIOUS=ROOT/'output/imagegen/awakening-v6'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,d):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 for name in ['prompts','raw','records','imports','review','references','baseline']:(OUT/name).mkdir(parents=True,exist_ok=True)
 (OUT/'.gdignore').write_text('')
 oldjobs=read(PREVIOUS/'jobs.json');selection=read(PREVIOUS/'selected.json')
 directory=ROOT/'art/characters/nezuko/awakening'
 if not (OUT/'baseline/atlas.json').exists():
  for path in directory.glob('atlas*'):
   if path.suffix in ['.png','.json']:shutil.copyfile(path,OUT/'baseline'/path.name)
  preserved={}
  for path in sorted((ROOT/'art/characters').rglob('*')):
   if path.is_file() and not (path.parent==directory and path.name.startswith('atlas')):
    preserved[path.relative_to(ROOT).as_posix()]=digest(path)
  save(OUT/'preserved-runtime.json',preserved)
 baseline=read(OUT/'baseline/atlas.json')
 idle_source=Image.open(PREVIOUS/'raw/nezuko-idle.png').convert('RGBA')
 idle_parts=components(cyan_matte(idle_source),6,3)
 # A single approved game pose at its native drawing scale, no concept-art reinterpretation.
 ref=Image.new('RGB',(512,560),(0,255,255));sprite=clean(idle_parts[0][1],True)
 ref.paste(sprite,((512-sprite.width)//2,40),sprite)
 ref.save(OUT/'references/approved-game-idle.png')
 # Direct source-size preview: stable 1:1 packing in the game's own 1024x640 canvas.
 samples=['idle','walk','dash_forward','jump','crouch','stand_heavy','blood_kick','awakened_combo']
 grid=Image.new('RGB',(4*384,2*324),'#182438');draw=ImageDraw.Draw(grid);pages={}
 for n,clip in enumerate(samples):
  i=0 if clip=='idle' else len(baseline['clips'][clip]['frames'])//2;e=baseline['clips'][clip]['frames'][i]
  if e['texture'] not in pages:pages[e['texture']]=Image.open(OUT/'baseline'/e['texture']).convert('RGBA')
  x,y,w,h=e['region'];frame=Image.new('RGBA',tuple(baseline['canvas_size']));frame.alpha_composite(pages[e['texture']].crop((x,y,x+w,y+h)),tuple(e['offset']))
  crop=frame.crop((128,48,896,640)).resize((384,296),Image.Resampling.LANCZOS);at=((n%4)*384,(n//4)*324+28);grid.paste(crop,at,crop)
  draw.text((at[0]+8,at[1]-23),clip+' #'+str(i),fill='white');draw.line((at[0],at[1]+260,at[0]+383,at[1]+260),fill='#8490a0')
 grid.save(OUT/'review/before-fixed-scale.jpg',quality=95)
 jobs=[]
 for original in oldjobs:
  job=copy.deepcopy(original);clip=job['metadata']['clip'];old=copy.deepcopy(original);old.update(selection.get(old['id'],{}));meta=job['metadata']
  count,cols,rows=meta['count'],meta['columns'],meta['rows']
  if clip=='idle':
   job.update(out=old['out'],prompt=old['prompt'],references=old['references'],group='preserved',skip_reason='Approved game idle is preserved pixel-for-pixel; no generation.')
   shutil.copyfile(PREVIOUS/'records/nezuko-idle.json',OUT/'records/nezuko-idle.json')
   job['metadata']['registration_profile']='preserve-v6-idle';jobs.append(job);continue
  # The shipped v6 drawing is pose choreography only; the approved idle owns anatomy.
  source=Image.open(ROOT/old['out']).convert('RGBA');native=np.asarray(source)
  keyed=source if np.mean(native[:,:,3]<8)>.30 else cyan_matte(source)
  parts=components(keyed,count,cols)
  guide=Image.new('RGB',(cols*512,rows*512),(0,255,255))
  for i,(_,pose) in enumerate(parts):
   pose=clean(pose,True);pose.thumbnail((472,472),Image.Resampling.LANCZOS)
   guide.paste(pose,((i%cols)*512+(512-pose.width)//2,(i//cols)*512+492-pose.height),pose)
  guide_path=OUT/'references'/('pose-'+clip+'.png');guide.save(guide_path)
  attacks=clip in ['stand_light','stand_heavy','crouch_light','crouch_heavy','air_light','air_heavy','body_stand_light','body_stand_heavy','body_crouch_light','body_crouch_heavy','body_air_light','body_air_heavy','blood_kick','rising_kick','spinning_kick','blood_burst','awakened_combo','throw','throw_forward','throw_success']
  mouth=('Facial acting is timed with the action: preparation mouth relaxed/closed; active strike frames mouth visibly open in a short forceful exhale or battle shout, small upper fangs visible, tense brow; recovery closes the jaw again. For multi-hit attacks vary restrained open exertion and clenched teeth with the separate kicks. The jaw opens without enlarging the skull. Avoid a giant mouth, comic grin, tongue display, or one identical closed-mouth expression throughout.' if attacks else 'Facial acting: calm closed mouth for locomotion and guard; brief parted lips/gritted teeth for strain or hit reaction; an open exhale at the central power release of awakening_start. No permanent screaming or comical expression.')
  extra=''
  if clip in ['walk','walk_back']:extra='Walk with arms naturally low, match the idle upright leg length and torso length exactly. Do not hunch or shorten the legs.'
  if clip=='awakening_start':extra='Fixed feet throughout. Last two frames settle into the EXACT image 1 arms-down idle stance and body proportions.'
  if clip in ['crouch','guard_low']:extra='Crouch by bending the same long limbs and torso from image 1. Do not give the crouching character a larger head or thicker trunk.'
  prompt=f'''Use case: identity-preserve
Asset type: final anime fighting-game sprite animation, Nezuko demon awakening, {clip}.
Input image 1 is the APPROVED IN-GAME IDLE. It is the sole anatomy, facial identity, costume, coloring and drawing-style master. Re-pose this exact character as if animating the same rigidly proportioned model. Preserve its small head-to-body ratio, long athletic limbs, narrow waist, shoulder width and stature exactly.
Input image 2 is ONLY the chronological choreography guide for {clip}: {count} poses in {cols} columns x {rows} rows. Keep these action directions, limb gestures, readable silhouettes, chronological sequence, phase changes and contacts. Its head and body proportions are WRONG and must be corrected from image 1. Never copy its big head or short stocky body.
Primary request: redraw every action frame from the SAME MODEL as image 1. The skull crown-to-chin size and shoulder-to-pelvis length must stay constant through all frames; crouching, kneeling, jumping, rotating, extended kicks or hair spread do not resize the person. Upright anatomical height excluding horn is about 6.2 head-lengths, matching image 1. No chibi, oversized eyes/head, shortened legs, thicker body, growth or shrinking in mid-action. Keep the face slim and the eye size identical to the idle master.
{extra}
{mouth}
Keep single ivory horn on anatomical right forehead, pink slit eyes, facial vine markings, long black hair with orange tips, ribbon, bare vine-marked legs, asymmetrical pink hemp-leaf kimono, checker obi/green cord, cocoa haori with intact shoulders and worn edges, calf wraps and sandals. Preserve opaque overlapping kimono over chest and pelvis through every pose; neutral combat depiction, no breast emphasis, no underwear view. No bamboo/muzzle, no pants, no extra limbs. Detailed clean theatrical anime ink lines and consistent cel shading exactly like image 1.
Sheet geometry: {cols*512} x {rows*512}, {cols} equal columns x {rows} equal rows, EXACTLY {count} separate full-body figures in row-major order. Use ONE FIXED anatomical ruler across the entire sheet: an upright character would be about 430 pixels tall from skull crown to soles, skull crown-to-chin about 69 pixels; apply the same physical drawing scale to every pose. Crouched and horizontal poses leave more blank space instead of growing. Position each body comfortably inside its cell. Never enlarge compact poses to fill a cell; never shrink an extended leg pose. Complete horn, hands, hair and feet; clean wide gutters.
Flat solid CYAN #00ffff background throughout, no floor, shadows, gradient, effects, aura, particles, captions, borders, logos or watermark. Do not include the idle reference as an extra cell.
'''
  pp=OUT/'prompts'/(job['id']+'.txt');pp.write_text(prompt,encoding='utf-8')
  job.update(out=(OUT/'raw'/(job['id']+'.png')).relative_to(ROOT).as_posix(),prompt=pp.relative_to(ROOT).as_posix(),references=[(OUT/'references/approved-game-idle.png').relative_to(ROOT).as_posix(),guide_path.relative_to(ROOT).as_posix()],size=f'{cols*512}x{rows*512}',group='pilot' if clip in ['walk','crouch','awakened_combo'] else 'awakening')
  job['metadata']['cell']=[512,512];job['metadata']['registration_profile']='idle-head-ruler-v7';job['metadata']['facial_acting']='exertion' if attacks else 'contextual'
  jobs.append(job)
 save(OUT/'jobs.json',jobs)
 save(OUT/'authorization.json',dict(service='https://cpa2.8201128.xyz',integration_authorized=True,reference=(OUT/'references/approved-game-idle.png').relative_to(ROOT).as_posix(),scope='Preserve approved Nezuko awakened idle; correct all dynamic proportions and action expressions including standalone MAX.',evidence='User previously authorized this CPA endpoint and direct integration; current request authorizes dynamic appearance corrections.'))
 save(OUT/'master.json',dict(source='output/imagegen/awakening-v6/raw/nezuko-idle.png',source_sha256=digest(PREVIOUS/'raw/nezuko-idle.png'),preserved_idle=baseline['clips']['idle'],reference_frame=0,reference='references/approved-game-idle.png',target_skull_length=59.5,measurement='Crown-to-chin excludes horn and loose hair; final measurement follows visual annotation.'))
 print('Prepared',len(jobs)-1,'dynamic sheets; idle preserved; 3 pilots.')
if __name__=='__main__':main()
