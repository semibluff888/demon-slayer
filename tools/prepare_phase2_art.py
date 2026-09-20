"""Stage-two pose briefs; network calls stay in existing run_art_production.ps1."""
import json
from prepare_art_production import STYLE, IDENTITY, write_job, OUT

BODY = {
 'tanjiro': {
  'body_stand_light': 'Compact HILT BUMP right: guard, draw elbow back, drive pommel at chest height, short contact, retract elbow, sword guard. Sword kept close blade upward. Not a slash.',
  'body_stand_heavy': 'Powerful FRONT KICK right: guard, load hip, raise knee, extend foot, full sole contact at waist, recoil knee, lower leg, recover weight, sword guard. Katana stays close.',
  'body_crouch_light': 'LOW ELBOW BUMP while deeply crouched: low guard, tuck elbow, drive elbow right at thigh level, compact contact, pull elbow back, low sword guard. Remain low throughout.',
  'body_crouch_heavy': 'LOW SWEEP KICK right: crouched guard, lower hips, coil supporting leg, extend other leg along floor, full sweep contact at ankle level, follow through, tuck leg, regain crouch, crouched sword guard. No sword swing.',
  'body_air_light': 'Airborne KNEE STRIKE right: descending guard, chamber knee, drive bent knee right, knee contact, draw knee in, extend feet for landing. Sword held close. No floor, pelvis fixed.',
  'body_air_heavy': 'Airborne DOWNWARD KICK: airborne guard, tuck hips, lift knee, drive foot diagonally DOWN RIGHT, extended sole contact, retract leg, gather knees, extend feet, landing anticipation. Sword close, pelvis fixed, no floor.',
 },
 'zenitsu': {
  'body_stand_light': 'Short SNAP KICK from low iaido guard: hand on hilt, lift front heel, snap toe right at thigh height, short contact, retract foot, iaido guard. Sword stays sheathed.',
  'body_stand_heavy': 'Agile strong SIDE KICK: iaido guard, shift supporting foot, chamber knee, drive heel right at waist, full side kick contact, recoil knee, set foot down, turn hips, low iaido guard. Sword sheathed.',
  'body_crouch_light': 'Tiny LOW TOE KICK crouched: low iaido ready, shift weight back, flick toe right at ankle height, short contact, retract toe, low guard. Never stand. Sword sheathed.',
  'body_crouch_heavy': 'LOW LEG REAP: deep iaido crouch, lower hips, pivot foot, extend heel right along floor, full sweeping contact at ankle height, follow through low, recoil leg, balance, low iaido guard. Sword sheathed.',
  'body_air_light': 'Airborne SNAP KICK right: airborne ready, chamber knee, snap foot at thigh height, short contact, retract knee, extend feet for landing. Sword sheathed, pelvis fixed, no floor.',
  'body_air_heavy': 'Airborne SCISSOR KICK: ready, gather knees, chamber front leg, drive foot diagonally down right while rear leg counterbalances, full heel contact, retract, gather, descend anticipation, feet below hips. Sword sheathed, pelvis fixed, no floor.',
 }
}
SHARED = {
 'roll_forward': (12,4,'GROUNDED shoulder roll toward RIGHT, never aerial: 1 guard, 2 squat reach right, 3 tuck head shoulder touches floor, 4 curled shoulder, 5 back on floor feet over head, 6 hips turn low, 7 feet rotate under hips, 8 low crouch facing RIGHT, 9 feet plant, 10 vulnerable kneel finding sword hilt, 11 straighten, 12 sword guard. Sheathed sword; all rolling body contacts share ground baseline. No jump.', 'feet', [0,1,2,4,6,9,12,15,18,20,23,26]),
 'roll_back': (12,4,'GROUNDED backward shoulder roll LEFT starting RIGHT-facing: 1 guard, 2 squat backward, 3 sit curl back, 4 shoulders touch floor feet lift right, 5 legs curl overhead left, 6 shoulder turns over, 7 legs tuck under, 8 crouch facing RIGHT, 9 feet plant, 10 vulnerable kneel finding hilt, 11 straighten, 12 guard facing RIGHT. Sword sheathed. Contacts touch common ground; no aerial backflip.', 'feet', [0,1,2,4,6,9,12,15,18,20,23,26]),
 'throw_forward': (12,4,'FORWARD collar-and-arm throw, rival initially RIGHT lands further RIGHT: 1 grasp wrist right, 2 grasp lapel, 3 draw elbows in, 4 plant rear leg, 5 turn hips right, 6 lift and pull through forward arc, 7 drive hands down RIGHT, 8 deep forward lunge hands down right, 9 slam contact right, 10 release, 11 balance, 12 sword guard RIGHT. Draw ONLY thrower, no rival. Never over-shoulder back throw. Sword sheathed; feet ground.', 'feet', [0,3,5,8,10,13,15,18,20,23,26,29]),
 'thrown_forward': (12,4,'ONLY victim of FORWARD throw initially facing LEFT: 1 wrist caught arm left, 2 lapel caught, 3 stagger right, 4 torso pulled sideways right, 5 hips rise legs fold, 6 body sideways airborne, 7 fall onto back right, 8 horizontal head LEFT feet RIGHT, 9 back hits ground head LEFT feet RIGHT, 10 compress, 11 limbs settle, 12 lying on back. No thrower. Sword sheathed. Pelvis x50% y55% frames1-8; last four grounded.', 'pelvis', [0,3,5,8,10,13,15,18,20,23,26,29]),
 'throw_tech': (6,3,'THROW ESCAPE facing RIGHT: 1 forearms brace across chest breaking grip, 2 push unseen rival wrist outward right, 3 open hands deflect grip, 4 pull hands back toward hilt, 5 plant feet regain balance, 6 sword guard. No rival, attack or slash. Sword sheathed.', 'feet', [0,2,4,6,8,10]),
}
SPECIAL = {
 'tanjiro': {
  'water_vortex': (12,4,'Planted horizontal rotational katana vortex: frames1-3 lower stance wind blade left; 4 horizontal cut RIGHT; 5 torso turns; 6 sword around back; 7 SECOND waist-height cut RIGHT; 8 follow through; 9 settle sword low; 10 decelerate; 11 reset feet; 12 guard. Two contacts frames4,7. Never somersault. No water effects.'),
  'water_dragon': (15,5,'Flowing FOUR-cut sword combination: frames1-3 gather low and wind sword; 4-5 first horizontal rising cut / recoil; 6-7 second descending cut / recoil; 8-9 third return cut / recoil; 10-11 fourth upward finish / recoil; 12-15 brake, lower sword, reset feet, guard. FOUR distinct contact poses frames4,6,8,10. Attacks RIGHT, increasing hip rotation. No water, dragon or effects.'),
  'sun_arc': (12,4,'Hinokami Kagura Clear Blue Sky ONE massive circular slash: frames1-4 breathe low, gather legs, blade high, wind torso; 5-7 complete vertical circle, curl diagonal then upside down in6 then unfold RIGHT; 8-12 land low, decelerate sword, brace knees, lift chest, sword guard. ONE decisive circle. Pelvis centered for rotation. No fire or effects.'),
 },
 'zenitsu': {
  'iai_return': (12,4,'Game-original retreat and return iaido: frames1-3 face RIGHT step/lean LEFT hand on hilt; 4 draw horizontal cut RIGHT; 5 extended contact; 6 twist hips back; 7 SECOND return cut RIGHT at waist; 8 follow through; 9 slow blade; 10 sheath; 11 reset feet; 12 low guard. Two contacts. Grounded, no upward slash or electricity.'),
  'sixfold': (18,6,'Thunderclap SIXFOLD: SIX low iaido bursts RIGHT. Frames1-3 ready, hand hilt, deep coil. EXACTLY SIX two-frame pairs: 4-5 horizontal dash-cut/recoil; 6-7 diagonal cut/recoil; 8-9 low rising cut/recoil; 10-11 horizontal cut/recoil; 12-13 descending cut/recoil; 14-15 final long straight slash/brake. Frames16-18 brake, sheath, low guard. All attacks RIGHT, root fixed in cell. NO electricity trails clones or effects.'),
  'godspeed': (15,5,'Godspeed MAX in THREE bursts RIGHT: frames1-4 calm breath, hand hilt, knee compress, deepest coil; 5-6 explosive horizontal draw-cut body almost horizontal/gather; 7-8 second low diagonal dash-cut/gather; 9-10 final long finishing slash/brake; 11-15 braking foot, hold blade, withdraw, slowly sheath, low guard. THREE contacts frames5,7,9. No electricity, clones or effects.'),
 }
}

def main():
 jobs=json.loads((OUT/'jobs.json').read_text(encoding='utf-8-sig'))
 existing={j['id'] for j in jobs}
 for cid in IDENTITY:
  specs={}
  for clip,motion in BODY[cid].items():
   n=6 if clip.endswith('light') else 9
   specs[clip]=(n,3,motion,'pelvis' if '_air_' in clip else 'feet',[],'phase2-basics-'+cid)
  for clip,s in SHARED.items(): specs[clip]=(*s,'phase2-basics-'+cid)
  for clip,(n,cols,motion) in SPECIAL[cid].items(): specs[clip]=(n,cols,motion,'pelvis' if clip=='sun_arc' else 'feet',[],'phase2-specials-'+cid)
  for clip,(n,cols,motion,anchor,timeline,group) in specs.items():
   aid=cid+'-'+clip+'-phase2-v1'
   if aid in existing: continue
   rows=(n+cols-1)//cols
   refs=['output/imagegen/anime-v2/raw/'+cid+'-model.png','output/imagegen/anime-v2/raw/'+cid+('-idle-v2.png' if cid=='tanjiro' else '-idle.png')]
   prompt=('Use case: stylized-concept\nAsset: chronological hand-drawn fighting game animation sheet.\n'+STYLE+'\n'+IDENTITY[cid]+'\n'
    'Input image1: strict costume, identity and colors. Input image2: strict head, hand, limb proportions and moonlit shading.\n'
    f'Exactly {n} complete single-character drawings in an invisible REGULAR {cols}-column x {rows}-row grid. Read left to right then top to bottom. Every drawing is the NEXT motion pose, not a duplicate hold.\n'
    'Nominal cell512x512: standing anatomy height350px, head about50px. SAME anatomical scale EVERY frame; never enlarge crouching or horizontal bodies. Empty space intentional.\n'
    'Whole hair, feet, limbs, katana and scabbard INSIDE each cell with generous gaps. No second person, effects, trails, floor line, shadow, text or grid.\n'
    'Root x50% each cell; grounded contact baseline y90%. Airborne pelvis x50% y55%; no vertical translation across airborne cells.\n'
    'Motion: '+motion+'\n'
    'Uniform pure HOT MAGENTA #ff00ff all empty pixels. Crisp ink outlines no magenta rim. Same believable young swordsman proportions as reference, no chibi. Sword identity visible in guard and recovery.')
   phase={'water_vortex':[3,9],'iai_return':[3,9],'water_dragon':[3,11],'sun_arc':[4,7],'sixfold':[3,15],'godspeed':[4,10]}.get(clip,[n//3,n*2//3])
   write_job(jobs,aid,group,prompt,f'{cols*512}x{rows*512}',refs,dict(character=cid,clip=clip,count=n,columns=cols,rows=rows,loop=False,fps=18,anchor_mode=anchor,root_fraction=0.5,standing_fraction=350/512,phase_breaks=phase,timeline=timeline,segment_sync=clip in ['water_vortex','iai_return','water_dragon','sixfold','godspeed']))
 for job in jobs:
  if job['id']=='zenitsu-body_crouch_heavy-phase2-v1':
   job['metadata'].update(frame_order=[1,2,3,4,5,6,7,8],phase_breaks=[2,5],editorial_note='Omit upright source frame 0; retain continuous low sweep.')
 (OUT/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('Prepared phase-two jobs; existing requests preserved.')
if __name__=='__main__': main()
