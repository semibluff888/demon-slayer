"""Versioned art briefs; all network requests use the existing CPA helper."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/roster-v1'
STYLE="""Premium hand-drawn Japanese anime fighting-game production art, Demon Slayer style.
Precise dark ink contours, normal anatomical proportions, recognizable expressive faces,
consistent costume, clean two-tone cel shading, neutral key light and subtle cool rim.
No photorealism, 3D, chibi, text, labels, watermark, UI or cast shadows."""
PROFILES={
 'nezuko':dict(name='灶门祢豆子',key='CYAN #00ffff',rgb=[0,255,255],identity="""Nezuko Kamado. Long black hair with orange tips, pink eyes, pink ribbon,
green bamboo muzzle with red cord, pink hemp-leaf patterned kimono, red-and-white obi,
long dark brown haori, white leg wraps and pink-strapped sandals. Youthful face,
modest intact outfit. Normal form has no horn or vine marks. UNARMED, never a sword."""),
 'akaza':dict(name='猗窝座',key='GREEN #00ff00',rgb=[0,255,0],identity="""Akaza. Athletic muscular adult male martial artist, short bright pink spiky hair,
golden eyes, pale skin with symmetrical dark blue stripe tattoos across face, arms and torso,
cropped sleeveless magenta vest, loose white trousers, dark blue sash, blue bead anklets,
bare feet. Confident martial guard, no weapons.""")}
# Each behavior has its own new drawings, never recolored old sprites.
CLIPS={
'idle':(6,'Breathing ready-stance cycle, hands guard chest, feet planted.',True),
'walk':(6,'Forward walking cycle to RIGHT, alternating contact, passing and extension.',True),
'walk_back':(6,'Defensive backstep cycle LEFT while facing RIGHT.',True),
'crouch':(6,'Lower gradually into deep crouch; last three drawings remain low.',False),
'jump':(6,'Takeoff crouch, rise, tucked apex, descend, landing crouch, recover.',False),
'guard':(6,'Raise forearms, absorb a strike from right, hold crossed-arm standing guard.',False),
'guard_low':(6,'Deep crouching crossed-arm guard, brace low throughout.',False),
'hit':(6,'Recoil from a hit from right, stagger back left, regain balance. No wounds.',False),
'knockdown':(6,'Stagger, lose balance, fall back, contact floor, settle, lie horizontal head LEFT.',False),
'throw':(6,'Reach to grab imaginary opponent right, miss, retract and recover. Only one person.',False),
'victory':(6,'Relax guard, straighten, lift chin, hold characteristic winning stance.',False),
'stand_light':(6,'One quick standing lead-hand palm or claw strike. Ready, windup, extend, contact, recoil, ready.',False),
'stand_heavy':(6,'One powerful rear-hand punch or claw sweep. Coil, windup, rotate, extend right, follow through, ready.',False),
'crouch_light':(6,'Quick low crouching palm or claw jab; remain low through six attack phases.',False),
'crouch_heavy':(6,'Strong crouching rising palm or claw strike, bent knees throughout six phases.',False),
'air_light':(6,'Airborne short palm or claw strike, knees tucked, windup/contact/recovery.',False),
'air_heavy':(6,'Airborne heavy downward fist or claw strike, windup/contact/follow-through/recovery.',False),
'body_stand_light':(6,'Standing lead-leg snap kick right, knee lifts, extends, contacts, retracts.',False),
'body_stand_heavy':(6,'Standing strong roundhouse kick right at chest height, supporting foot planted.',False),
'body_crouch_light':(6,'Quick crouching low kick right, low torso throughout.',False),
'body_crouch_heavy':(6,'Strong crouching ankle-height sweep right, deep low stance, recover low.',False),
'body_air_light':(6,'Airborne quick knee and snap kick right, retract legs.',False),
'body_air_heavy':(6,'Airborne powerful diagonal downward kick right, extend then retract.',False),
'dash_forward':(6,'Low dash RIGHT, lean and drive feet, brake into guard.',False),
'dash_back':(6,'Evasive dash LEFT while facing RIGHT, recover guard.',False),
'jump_forward':(12,'Complete forward somersault, crouch, launch, rotate upside-down, uncoil, land, recover.',False),
'jump_back':(12,'Complete backward somersault, launch left, invert, land, recover facing right.',False),
'roll_forward':(12,'Grounded forward tumble right, tuck over shoulder, low rotation, recover.',False),
'roll_back':(12,'Grounded backward tumble left, tuck and rotate, recover facing right.',False),
'throw_forward':(12,'Grab imaginary opponent right, pull onto hip, rotate, throw forward right, recover. Only one person.',False),
'throw_success':(12,'Grab imaginary opponent right, pivot and throw BEHIND left, release facing left, recover. Only one person.',False),
'thrown_forward':(12,'Throw VICTIM: lifted, inverted, falls flat on back head LEFT by frame 9, stays lying. No other person.',False),
'thrown':(12,'Backward throw VICTIM: lifted, inverted, arcs, falls flat head RIGHT by frame 9, stays lying. No other person.',False),
'throw_tech':(6,'Break grab: brace, push palms forward, step back, recover.',False),
'round_intro':(12,'Introduction: calm stance, deliberately raise hands, finish fighting guard.',False),
'round_victory':(12,'Victory: relax, face viewer, characteristic confident gesture, settle and hold.',False),
'round_defeat':(12,'Defeat: recoil, fly slightly back, back touches ground by frame 7, settle and stay horizontal. No gore.',False)}
SPECIALS={
'nezuko':{
'blood_kick':(9,'Coil then leap into a long side kick RIGHT, retract and land. No effects.'),
'rising_kick':(9,'Launch high rising kick toward RIGHT, extend upward, descend, land.'),
'spinning_kick':(12,'Two spinning kicks RIGHT, clear contact frames 5 and 8, recover.'),
'blood_burst':(12,'Gather arms then sweep hands with forceful kicking finish, four-beat explosive attack. No flames.'),
'awakened_combo':(12,'AWAKENED NEZUKO: one horn on right forehead, vine marks, NO bamboo muzzle. Intact modest kimono and haori. Three powerful lunging kicks RIGHT then settle. No flames.')},
'akaza':{
'air_type':(9,'Plant feet, wind fist, punch air RIGHT at chest height, hold extension, recover. No shockwave.'),
'crown_splitter':(9,'Coil, kick vertically upward toward RIGHT above head height, lower leg, recover.'),
'disorder':(12,'Rapid alternating punches RIGHT in two contact groups, finish fist then recover.'),
'annihilation':(12,'Gather strength, lower center, devastating single lunging punch RIGHT, follow-through, recover.'),
'blue_afterglow':(12,'Six rapid alternating martial punches and palms RIGHT from wide stance, final double palm, recover. No energy.')}}
def main():
 jobs=[]
 def add(id,group,prompt,size,refs=(),meta=None):
  p=OUT/'prompts'/(id+'.txt');p.parent.mkdir(parents=True,exist_ok=True)
  p.write_text(prompt.strip()+'\n',encoding='utf-8')
  jobs.append(dict(id=id,group=group,prompt=p.relative_to(ROOT).as_posix(),out=(OUT/'raw'/(id+'.png')).relative_to(ROOT).as_posix(),size=size,references=list(refs),metadata=meta or {}))
 for cid,p in PROFILES.items():
  basic=STYLE+'\n'+p['identity'];bg='\nFeatureless solid '+p['key']+' background and gutters. No shadows.'
  add(cid+'-model','foundation',basic+'\nThree full-body model views in ONE row: front, three-quarter right, side right. Same scale, neutral guard, all hair and feet visible.'+bg,'2048x1152')
  ref=(OUT/'raw'/(cid+'-model.png')).relative_to(ROOT).as_posix()
  add(cid+'-portrait','portraits',basic+'\nReference is strict identity. ONE full-body hero portrait facing RIGHT in three-quarter view, spectacular martial pose, flowing costume. Entire body visible, fills 86 percent height, clear eyes.'+bg,'1024x1536',[ref],dict(character=cid,matte=p['rgb']))
  add(cid+'-face','portraits',basic+'\nReference is strict identity. ONE head-and-shoulders portrait, three-quarter facing RIGHT. Hair top at 5 percent height, chin at 64 percent. Complete head and shoulders, intense expression.'+bg,'1024x1024',[ref],dict(character=cid,matte=p['rgb']))
  if cid=='nezuko':
   add(cid+'-awakened-face','portraits',basic+'\nReference is normal identity. ONE awakened head-and-shoulders portrait: one horn on right forehead, vine marks, NO bamboo muzzle, fierce eyes. Complete head and horn, modest clothing. Same framing as HUD.'+bg,'1024x1024',[ref],dict(character=cid,matte=p['rgb']))
  clips=dict(CLIPS);clips.update({k:(v[0],v[1],False) for k,v in SPECIALS[cid].items()})
  for clip,(count,action,loop) in clips.items():
   cols=3 if count<=9 else 4;rows=(count+cols-1)//cols
   prompt=basic+f'\nReference is strict identity. EXACTLY {count} consecutive full-body sprite drawings, {cols} columns and {rows} rows, equal cells, chronological row-major order, no grid lines.\n'
   prompt+='Face RIGHT unless motion says otherwise. Fixed side camera and SAME anatomy scale in every frame. Standing height 65 percent of cell height. Root at 44 percent cell width; floor at 88 percent cell height. NEVER enlarge crouched or horizontal poses. All limbs and cloth inside each cell, generous gutters.\nMotion: '+action+'\nDistinct sequential preparation/contact/recovery poses. No opponent, weapons or magic effects.'+bg
   meta=dict(character=cid,clip=clip,count=count,columns=cols,rows=rows,loop=loop,fps=12,matte=p['rgb'],anchor_mode='pelvis' if clip in ['jump','jump_forward','jump_back','roll_forward','roll_back','thrown','thrown_forward','air_light','air_heavy','body_air_light','body_air_heavy'] else 'feet',segment_sync=clip in ['spinning_kick','blood_burst','awakened_combo','disorder','blue_afterglow'])
   add(cid+'-'+clip,'animation',prompt,f'{cols*768}x{rows*768}',[ref],meta)
 for sid,desc in {
 'infinity_castle':'Infinity Castle: impossible layered Japanese timber halls, warm gold shoji lamps, distant suspended stairs and geometric beams. Broad EMPTY level wooden foreground fighting floor. Blackened wood, amber and soft gold.',
 'entertainment_district':'Taisho-era Japanese entertainment district at night: elegant wooden two-storey facades, crimson lanterns, magenta silk curtains, indigo sky. Broad EMPTY flat stone street with lantern reflections. No people or legible signs.'}.items():
  add(sid+'-master','foundation',f"""Premium painted anime 2D fighting-game stage panorama.
{desc}
Horizontal side camera, level horizon. Refined crisp architecture, atmospheric distant detail.
3:1 image. Compose usable continuous 4:1 panorama inside CENTRAL 75 percent of image height;
top and bottom 12.5 percent will be cropped. Fighter foot-contact line EXACTLY 72 percent of FULL image height.
Everything below contact line is clear flat fighting lane. Stairs only far in background.
No foreground obstacles, people, text, logos, borders or vignette. Fully painted side edges.
Visual interest above fighters, subdued contrast behind their bodies, dramatic readable lighting.""",'3840x1280',meta=dict(stage=sid))
 for key,desc in {'blood-flame':'Sweeping arc of bright pink and crimson supernatural flame flowing LEFT to RIGHT, white-hot inner core, ink edges, curling tongues and embers.','shockwave':'Compressed icy-blue and cyan martial energy shockwave LEFT to RIGHT, broad circular pressure ring, sharp trailing streaks, white core.','compass':'Symmetrical twelve-point snowflake compass magic sigil, icy blue, flat front-on, fine geometric linework, clear open center, no letters or numbers.'}.items():
  add('fx-'+key,'effects',STYLE+'\nONE isolated game effect. '+desc+'\nPure BLACK backdrop. Entire effect with margins. No person or ground.','1536x1024')
 (OUT/'raw').mkdir(parents=True,exist_ok=True);(OUT/'records').mkdir(exist_ok=True)
 existing=json.loads((OUT/'jobs.json').read_text(encoding='utf-8-sig')) if (OUT/'jobs.json').exists() else []
 known={j['id'] for j in existing}
 jobs=existing+[j for j in jobs if j['id'] not in known]
 (OUT/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2),encoding='utf-8')
 (OUT/'profiles.json').write_text(json.dumps(PROFILES,ensure_ascii=False,indent=2),encoding='utf-8')
 print(f'{len(jobs)} artwork jobs')
if __name__=='__main__':main()
