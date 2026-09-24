"""Prepare isolated CPA briefs; never writes production artwork."""
import json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools'))
from prepare_art_production import STYLE, IDENTITY
PLANS = {
 'tanjiro': [
  ('A', '礼仪', 'Collar adjustment, breathing, ceremonial sword guard.',
   'Start relaxed with blade low. Frames 1-5 lift left hand to straighten collar, right hand safely holds katana. 6-10 lower left hand and take a deep composed breath. 11-15 return left hand to sword, step into a balanced guard. 16-18 settle into familiar right-facing two-handed sword guard.',
   'Frames 1-6 gently lower blade and straighten shoulders. 7-12 slowly slide katana into left-hip scabbard with correct alignment. 13-18 give a small respectful bow of the head toward the opponent and stand calmly, hands relaxed.',
   'Frames 1-3 recoil backward from a blow from RIGHT. 4-6 lose balance and sink onto one knee. 7-9 tip to the LEFT, supporting hand briefly touches floor. 10-12 settle fully lying on the SIDE, head LEFT feet RIGHT, entire body touching ground.'),
  ('B', '水息', 'Low breathing stance, flowing sword gesture.',
   'Frames 1-6 lower hips with knees flexed, both hands at sword. 7-12 inhale and sweep blade in a small measured upward arc. 13-18 rise into a firm right-facing two-handed guard, haori gently settling. Water is added separately; draw no water.',
   'Frames 1-6 relax shoulders and turn blade outward. 7-12 make one controlled downward wrist flick, left hand near scabbard. 13-18 smoothly sheathe blade and finish with hand resting on hilt. Water is added separately.',
   'Frames 1-3 chest recoils backward, heels slide LEFT. 4-6 arms open slightly while grip stays secure, hips drop. 7-9 fall onto BACK, shoulders and hips contact floor. 10-12 settle flat supine, head LEFT feet RIGHT, knees relaxing.'),
  ('C', '火意', 'Resolute upward gaze, forceful sword lift.',
   'Frames 1-6 lower head and tighten both hands on sword, knees slightly bent. 7-12 lift eyes with fierce resolve and raise sword in a short strong diagonal arc. 13-18 settle blade into the familiar right-facing two-handed ready guard. Flame added separately.',
   'Frames 1-6 finish upright, blade angled out. 7-12 sweep katana once down and outward with confident restraint. 13-18 return both hands to hilt and hold blade lowered diagonally at the side, resolute gaze, haori settles. Flame added separately.',
   'Frames 1-3 absorb a heavy hit, torso hunches forward. 4-6 struggle down onto one knee. 7-9 supporting elbow gives way, torso falls forward toward RIGHT. 10-12 lie completely face-down with head RIGHT feet LEFT, safe blade extended away from body.'),
  ('D', '守护', 'Compassionate resolve, hand to chest.',
   'Frames 1-6 left palm briefly rests on chest, blade low in right hand, eyes calm. 7-12 lift head, place left hand on sword and take one small forward step. 13-18 settle into the familiar right-facing two-handed guard, compassionate determined expression.',
   'Frames 1-6 slowly lower guard, exhale, shoulders relax. 7-12 sheathe sword carefully. 13-18 smile subtly and give a respectful small nod toward opponent, left hand open near chest, no broad comedy.',
   'Frames 1-3 stumble backward under impact. 4-6 left palm reaches down to catch the falling body. 7-9 arm buckles and torso rolls gently onto side. 10-12 lie completely on left side, head LEFT feet RIGHT, one arm bent near chest.')
 ],
 'zenitsu': [
  ('A', '惊怯', 'Nervous to determined, restrained expressive acting.',
   'Frames 1-6 hunch shoulders nervously and glance sideways, one hand close to chest, sword safely low. 7-12 grip sword with both hands and inhale, small tremble in shoulders. 13-18 plant feet and resolve into the familiar right-facing ready guard, courage overcoming fear.',
   'Frames 1-6 open eyes, cautiously glance toward the defeated opponent, surprised relief. 7-12 sheathe sword with a slightly hurried but correct motion. 13-18 pat chest with free hand, exhale and relax shoulders, small relieved smile.',
   'Frames 1-3 recoil startled from a blow from RIGHT. 4-6 two unsteady backward steps LEFT, knees buckle. 7-9 lose balance and fall onto side. 10-12 settle fully lying on SIDE with head LEFT feet RIGHT, no sitting pose.'),
  ('B', '入静', 'Quiet concentration, eyes close, iaido calm.',
   'Frames 1-6 breathe slowly and close eyes, shoulders drop. 7-12 lower hips into compact iaido stance, left hand stabilizes scabbard, right hand grips hilt. 13-18 draw blade into the familiar right-facing low ready guard, tranquil focused face.',
   'Frames 1-6 lower blade with eyes closed. 7-12 slowly align blade with left-hip scabbard and sheathe with precise hands. 13-18 rest hand on hilt and stand still, eyes closed, haori settles.',
   'Frames 1-3 head and chest recoil, slide a little LEFT. 4-6 knees touch floor, torso folds. 7-9 arms give way and body tips forward RIGHT. 10-12 settle completely face-down, head RIGHT feet LEFT, blade lying safely alongside.'),
  ('C', '雷鸣', 'Compressed power and a crisp draw flourish.',
   'Frames 1-6 compress into a low ready stance, left hand on scabbard. 7-12 perform one short sharp draw-cut upward RIGHT, visibly distinct intermediate poses. 13-18 brake naturally and settle into the familiar right-facing sword guard. Lightning added separately.',
   'Frames 1-6 finish blade extension, still focused. 7-12 bring katana back smoothly and precisely into the scabbard. 13-18 close the hilt with a tiny decisive click gesture, stand upright and still. Lightning added separately.',
   'Frames 1-3 forceful recoil backward from RIGHT. 4-6 feet briefly leave ground, torso tilts LEFT without spinning. 7-9 horizontal back and hip contact ground. 10-12 settle fully supine, head LEFT feet RIGHT, legs relaxed.'),
  ('D', '梦醒', 'Drowsy to alert, small characterful contrast.',
   'Frames 1-6 head gently nods with drowsiness, eyelids heavy, katana safely low. 7-12 suddenly lift head and become alert, one sharp intake of breath, no exaggerated face distortion. 13-18 lower hips and settle into familiar right-facing sword guard.',
   'Frames 1-6 slowly open eyes and glance at the scene, quietly puzzled. 7-12 relax shoulders and begin careful sheathing. 13-18 finish sheathing and give a small sleepy relieved smile with slight head tilt.',
   'Frames 1-3 stagger with a heavy head droop after impact. 4-6 knees buckle and torso rocks forward. 7-9 elbows touch ground then fold. 10-12 lie completely face-down, head RIGHT feet LEFT, a final small settling of haori.')
 ]
}
def main():
 jobs, variants = [], []
 for char, variants_for_char in PLANS.items():
  for code, name, concept, intro, victory, defeat in variants_for_char:
   variants.append(dict(character=char, id=code, name=name, concept=concept))
   for clip, motion, count, cols in [('intro',intro,18,6),('victory',victory,18,6),('defeat',defeat,12,4)]:
    key = f'{char}-{code.lower()}-{clip}-v1'
    prompt = f"""Use case: stylized-concept
Asset: sequential 2D fighting-game character sprite sheet.
{STYLE}
{IDENTITY[char]}
Reference 1 locks character identity and costume. Reference 2 locks existing ready pose, anatomy and game drawing style.
Create EXACTLY {count} DIFFERENT chronological full-body drawings in EXACTLY {cols} columns and 3 rows. Read left to right, then next row. Equal cells with generous empty gutters, no visible grid.
Side view starting facing RIGHT. One continuous action: {concept}
{motion}
Interpolate body mechanics evenly between the described beats, each drawing advances the same action. Keep one consistent 6.5-7 head anatomical scale across every pose, including horizontal fallen poses. Maintain head size, hand size, limb length and costume motifs. Each cell has the same imagined floor baseline at 88 percent cell height. Standing anatomical height about 68 percent cell height. Character body centered horizontally in each cell. All hair, blade, hands and feet fit within cell with ample margins. Katana remains continuous, only one sword and one scabbard. Sheathing correctly moves blade into the scabbard; do not draw duplicate swords.
Pure solid HOT MAGENTA #ff00ff background and gutters. No pink reflections. Body and weapon only. No scenery, shadow, text, watermark, blood, water, fire, lightning, aura, trails or clones. Special effects will be rendered separately.
"""
    for folder in ['prompts','raw','records','assets','review','previews']:
     (HERE/folder).mkdir(parents=True,exist_ok=True)
    p=HERE/'prompts'/f'{key}.txt'; p.write_text(prompt,encoding='utf-8')
    jobs.append(dict(id=key,character=char,variant=code,clip=clip,count=count,columns=cols,rows=3,
      size=f'{cols*512}x1536',prompt=str(p.relative_to(ROOT)).replace('\\','/'),
      out=str((HERE/'raw'/f'{key}.png').relative_to(ROOT)).replace('\\','/'),
      references=[f'output/imagegen/anime-v2/raw/{char}-model.png',f'output/imagegen/anime-v2/raw/{char}-idle-v2.png' if char=='tanjiro' else f'output/imagegen/anime-v2/raw/{char}-idle.png']))
 (HERE/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2),encoding='utf-8')
 (HERE/'variants.json').write_text(json.dumps(variants,ensure_ascii=False,indent=2),encoding='utf-8')
 print(f'Prepared {len(jobs)} isolated motion sheets / 384 drawings.')
if __name__=='__main__': main()
