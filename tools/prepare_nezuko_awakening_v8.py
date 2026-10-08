"""Prepare targeted v8 motion assets from the user-approved idle and MAX model."""
import copy,hashlib,json,math,shutil
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/imagegen/awakening-v8';PREV=ROOT/'output/imagegen/awakening-v7'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
POSES={
'walk':[
'In-place walking contact: near leg extends forward RIGHT with heel touching ground, far leg extends behind LEFT with toes down. Arms low. Upright spine.',
'Down/passing: near foot travels under pelvis as weight transfers to it, far heel rises and far knee starts swinging forward; near knee bends only a little. Upright full-height torso.',
'Up/passing: near foot now a little behind pelvis, far foot swings forward RIGHT past supporting ankle. Long legs, subtle ankle push. Same head height.',
'Opposite contact: far leg forward RIGHT with heel down, near leg extends back LEFT with toes down. Exact opposite-leg phase of frame 0, same head and pelvis.',
'Down/passing opposite: far foot under pelvis bears weight, near heel lifts behind and near knee swings forward. Arms counter-swing gently.',
'Up/passing opposite: far foot a little behind pelvis, near foot swings forward RIGHT past supporting ankle. The NEXT frame is frame 0 near-leg contact. Seamless six-frame loop, do not return to stationary idle.'],
'walk_back':[
'Backward walking contact facing RIGHT: near leg reaches behind LEFT with toes contacting floor, far leg forward RIGHT bears weight. Upright full-height torso, arms low.',
'Backward weight transfer: near foot travels toward pelvis as body moves LEFT, far heel lifts in front. Keep exact same torso/head shape.',
'Backward passing: near leg supports under pelvis, far foot swings backward LEFT passing supporting ankle. Long legs, low relaxed arms.',
'Opposite backward contact: far leg reaches behind LEFT toes down, near leg forward RIGHT supports. Opposite-leg phase of frame 0.',
'Opposite backward transfer: far foot under pelvis supports, near heel lifts in front. Same body height.',
'Opposite backward passing: far leg supports, near foot swings backward LEFT past supporting ankle, ready to become frame 0. Seamless loop, no idle/reset frame.'],
'dash_forward':[
'Forward dash anticipation in shallow lunge, weight over front foot. Same long-legged MAX model, no deep compact crouch.',
'Powerful forward push: torso angled 30 degrees forward, rear leg extends long behind, leading knee rises. Arms low for balance.',
'Forward running stride: leading leg reaches RIGHT, rear leg stretches LEFT, both thighs and calves stay as long as the MAX side kick model.',
'Landing running stride: front foot touches, rear knee swings through; torso still leaning forward, long spine.',
'Opposite running stride: opposite leg reaches RIGHT, back leg extended behind, arms naturally counter-swing.',
'Exit dash in broad forward stance, torso rises toward idle while keeping long legs and full-sized body.'],
'dash_back':[
'Backward dash anticipation facing RIGHT, torso near upright and only shallow bend in knees, hands low.',
'Push off front foot to move LEFT, rear leg extends backward LEFT, front knee rises slightly, head remains facing RIGHT.',
'Airborne backward running stride, torso leans back only 10 degrees, long legs split in a wide athletic stride.',
'Rear foot lands LEFT and bears weight, forward leg swings backward under pelvis. Same long torso and small head.',
'Opposite backward running stride, long legs exchange roles, torso stable and head faces RIGHT.',
'Exit backward dash in broad balanced standing stance, full-height torso and legs.'],
'air_light':[
'Airborne preparation, long torso upright, knees lightly flexed and lower legs naturally extended down, one hand drawn near shoulder.',
'Wind up a quick palm, torso turns toward RIGHT; legs remain long and relaxed, one knee slightly bent.',
'Airborne straight palm strike RIGHT, mouth briefly open with effort, long rear leg trails down-left and front knee bends.',
'Palm follow-through with same full length arm and torso, toes pointed downward, small open exhale.',
'Retract palm while airborne, knees naturally flex to prepare for landing, do not fold into a tiny ball.',
'Airborne recovery with arms down and long legs descending, relaxed jaw.'],
'air_heavy':[
'Airborne upper-body preparation, long torso and slightly bent knees, rightward facing.',
'Raise rear forearm for a forceful downward claw, shoulder rotates, long legs trail down.',
'Strong airborne diagonal claw strike downward-right, mouth open in focused exertion, spine stays long.',
'Follow through the claw across front of body, rear leg still long and front knee bent, small head fixed.',
'Recover striking arm while airborne, knees flex a little, maintain long thighs and calves.',
'Airborne recovery, torso upright, arms settle and long legs extend toward landing.'],
'body_air_light':[
'Airborne ready, reference MAX raised-knee body model, one knee rises while opposite long leg trails downward.',
'Chamber forward knee to waist height, long torso upright, balance with low hands.',
'Quick airborne front kick RIGHT at waist height, entire long thigh and calf extend, mouth open in short exhale.',
'Retract kicking knee with opposite leg extended down-left, head and torso retain full proportions.',
'Lower knee partway while airborne, hands settle, preserve long limbs.',
'Airborne recovery with naturally extended legs ready to land, no grounded foot.'],
'body_air_heavy':[
'Airborne ready with full-sized MAX anatomy, long torso, rear leg trails down, hands balance.',
'Chamber knee high for a powerful airborne side kick, long thigh folds against torso.',
'Fully extend a powerful side kick RIGHT at chest height, exact long leg proportions of attached MAX kick, opposite leg extended down-left, mouth open.',
'Same airborne side kick follow-through, long reach and full pelvis/torso, small fangs, no oversized head.',
'Retract knee high, balance arms, long rear leg remains extended down.',
'Airborne recovery, torso rotates upright, legs begin lowering, mouth closes.'],
'blood_kick':[
'Arms-down approved idle, same tall MAX ready stature.',
'Long forward step, reference MAX anticipation and full leg length.',
'Low long lunge preparing launch; do not shrink torso or limbs.',
'Launch forward from rear foot, front knee chambers at waist, long rear leg trails.',
'Airborne fully extended side kick RIGHT, exact long MAX kicking leg and full body, mouth open shout.',
'Airborne kick follow-through, front leg extended, rear knee bends, same head and torso scale.',
'Retract kicking knee while descending, long rear leg extends toward landing.',
'Land into long split stance, knees absorb impact but same anatomy.',
'Recover to arms-down approved idle with same tall stature.'],
'rising_kick':[
'Arms-down approved idle, full MAX stature.',
'Shallow preparation crouch, long thighs bend, torso remains long.',
'Raise front knee while pushing rear foot off ground, prepare upward kick.',
'Launch upward, front knee near chest, opposite long leg extended downward.',
'Vertical rising kick: front leg extends almost vertically upward-right with full MAX thigh/calf length, opposite leg downward, mouth open shout.',
'Upward kick apex, extended leg still high, full-sized torso and small head.',
'Retract raised knee at apex, opposite leg extends down for balance, teeth clenched.',
'Descend with both long legs lowering naturally, arms balance.',
'Recover standing after landing, full tall approved idle stature.'],
'spinning_kick':[
'Arms-down approved idle with full MAX stature.',
'Step outward and turn hips preparing spin, spine long.',
'Chamber knee to waist while supporting leg remains long.',
'Begin rotational roundhouse kick RIGHT, kicking leg half extended, open exhale.',
'Fully extend first roundhouse side kick RIGHT at chest height, exact long leg of MAX, small open mouth.',
'Rotate through side/back three-quarter view; extended leg passes around, preserve full skeleton length.',
'Coil second kick with raised knee, same full MAX torso and supporting leg.',
'Fully extend second high roundhouse RIGHT with MAX leg length, open-mouth effort.',
'Follow through second high kick and turn back toward RIGHT, no shrinkage.',
'Retract knee, hips unwind, mouth closes.',
'Lower kicking foot and settle weight.',
'Arms-down approved idle with identical tall stature.'],
'blood_burst':[
'Arms-down approved idle, exact MAX full stature.',
'Long forward step with lowered hands opening, spine long.',
'Brace stance with only slight knee bend, draw hands toward body.',
'First explosive upward palm release, mouth opens briefly, long legs support full torso.',
'Extend arms outward and rise on long legs as power releases, focused open-mouth shout, no visual effects.',
'Channel second pulse with hands near chest and hips rotating, full MAX anatomy.',
'Raise leading knee like attached MAX knee-up pose, long supporting leg, mouth open exertion.',
'Fully extend powerful side kick RIGHT using exact long MAX leg model, mouth open shout.',
'Kick follow-through as power peaks, full-sized torso, long opposite leg supports.',
'Retract knee and lower arms, teeth clenched.',
'Lower kicking foot and recover posture, mouth relaxes.',
'Arms-down approved idle at identical full stature.'],
}

def main():
 if (OUT/'jobs.json').exists():raise SystemExit('v8 already prepared; preserve selections')
 for name in ['references','raw','prompts','records','imports','review','baseline']:(OUT/name).mkdir(parents=True,exist_ok=True)
 (OUT/'.gdignore').write_text('')
 runtime=ROOT/'art/characters/nezuko/awakening'
 for p in runtime.glob('atlas*'):
  if p.suffix in ['.json','.png']:shutil.copyfile(p,OUT/'baseline'/p.name)
 for src,dst in [(PREV/'references/approved-game-idle.png','approved-idle.png'),(PREV/'raw/nezuko-awakened_combo-part0.png','approved-max.png')]:shutil.copyfile(src,OUT/'references'/dst)
 preserved={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'art/characters').rglob('*') if p.is_file() and not (p.parent==runtime and p.name.startswith('atlas'))};save(OUT/'preserved-runtime.json',preserved)
 baseby={j['metadata']['clip']:j for j in read(PREV/'jobs.json')};jobs=[];generation=[]
 for clip,steps in POSES.items():
  job=copy.deepcopy(baseby[clip]);job.pop('source_sheets',None);job.pop('frame_overrides',None);job['id']='nezuko-'+clip;job['group']='targeted';job['metadata']['registration_profile']='model-ruler-v8';job['metadata']['columns']=3;job['metadata']['rows']=math.ceil(len(steps)/3);job['metadata']['cell']=[512,512]
  segments=[list(range(len(steps)))] if len(steps)<=9 else [list(range(0,6)),list(range(6,12))]
  sources=[]
  for part,indices in enumerate(segments):
   count=len(indices);j=copy.deepcopy(job);j['id']=job['id']+('-part'+str(part) if len(segments)>1 else '');j['group']='pilot' if clip in ['walk','dash_forward'] else 'targeted';j['out']=(OUT/'raw'/(j['id']+'.png')).relative_to(ROOT).as_posix();j['prompt']=(OUT/'prompts'/(j['id']+'.txt')).relative_to(ROOT).as_posix();j['references']=[(OUT/'references/approved-idle.png').relative_to(ROOT).as_posix(),(OUT/'references/approved-max.png').relative_to(ROOT).as_posix()];j['size']='1536x'+str(math.ceil(count/3)*512);j['metadata'].update(count=count,rows=math.ceil(count/3),frame_indices=indices)
   gait='For the walking cycle, keep pelvis at the same X position in every cell, face shape and torso nearly identical, skull at same Y with at most 4 pixels natural bob. Both rows are a SINGLE LOOP, not a story of moving rightward. Each foot changes role in order; last frame flows directly into first, without stationary idle or duplicate held steps.' if clip in ['walk','walk_back'] else ''
   prompt=f'''Use case: identity-preserve
Asset type: final polished 2D anime fighting-game sprite animation, Nezuko awakened {clip}.
Input image 1: APPROVED GAME IDLE, exact identity and standing stature.
Input image 2: APPROVED MAX ATTACK MODEL. The user specifically likes its full-sized body, long thighs/calves, torso length and small head in action. This image is the definitive ACTION ANATOMY reference. Re-pose that same rigid skeleton, rather than inventing shorter limbs. The target is exactly the same body size as MAX in EVERY action, including running and aerial strikes.
Primary request: {count} chronological full-body drawings, 3 equal columns by {math.ceil(count/3)} equal rows, row-major, all oriented RIGHT except explicitly turning kick poses.
Physical ruler for EVERY drawing: upright skull-crown-to-sole around 458 pixels, skull-crown-to-chin around 78 pixels excluding horn, hip-joint-to-sole leg length around 248 pixels, shoulder-to-pelvis around 138 pixels. Keep these lengths identical to the MAX reference during bending, running, rotation, and aerial poses. Never shorten thighs/calves or torso to fit cells; never enlarge skull to express effort. No chibi or round stocky anatomy. Extended leg poses can reach across a wider cell area; leave gutters and complete feet/hair/horn visible. Compact poses leave blank space. Hair tips must not hide which leg is nearer. Width/height fit is NOT an anatomical model.
{gait}
'''+ '\n'.join('Frame '+str(n)+' (action phase '+str(i)+'): '+steps[i] for n,i in enumerate(indices))+'''
Preserve the exact costume and rendering of both references: single right-forehead ivory horn, pink slit eyes, facial/limb vines, pink ribbon, long dark hair with orange tips, asymmetrical pink patterned kimono, checked obi/green cord, cocoa haori with intact shoulders, bare vine-marked legs, calf wraps and sandals. Opaque overlapping cloth covers chest and pelvis at all times, neutral combat framing. No bamboo, muzzle strap, leggings, extra limbs. Closed relaxed mouth in locomotion/preparation/recovery; active strikes use a modest open exhale/shout with small fangs. Crisp premium anime ink and cel shading. No opponent, aura, flames, speed streaks, floor, shadows, text, guides, frame borders or watermark. Pure solid CYAN #00ffff background. Do not add reference images as extra frames. Do not redraw unrelated moves.
'''
   (ROOT/j['prompt']).write_text(prompt,encoding='utf-8');generation.append(j);sources.append(dict(id=j['id'],out=j['out'],indices=indices,columns=3,rows=j['metadata']['rows'],prompt=j['prompt'],references=j['references']))
  job.update(out=sources[0]['out'] if len(sources)==1 else (OUT/'raw'/(job['id']+'-assembled.png')).relative_to(ROOT).as_posix(),prompt=sources[0]['prompt'],references=sources[0]['references'])
  if len(sources)>1:job['source_sheets']=sources
  jobs.append(job)
 save(OUT/'jobs.json',jobs);save(OUT/'generation-jobs.json',generation)
 save(OUT/'master.json',dict(base_atlas='baseline',preserve_unmodified_clips=True,reference_idle='references/approved-idle.png',reference_max='references/approved-max.png',target_clips=list(POSES),target_head_length=59.5,reason='User-approved v7 MAX defines action anatomy; fix cyclic translation and stature.'))
 save(OUT/'authorization.json',dict(service='https://cpa2.8201128.xyz',integration_authorized=True,scope='12 Nezuko motion clips only; preserve approved idle and MAX',evidence='Existing explicit CPA and direct integration authorization; current targeted user request.'))
 print('Prepared',len(jobs),'target clips,',sum(j['metadata']['count'] for j in jobs),'frames,',len(generation),'requests')
if __name__=='__main__':main()
