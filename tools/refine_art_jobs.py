"""Register targeted replacement requests without overwriting original generations."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/anime-v2'
jobs = json.loads((OUT / 'jobs.json').read_text(encoding='utf-8'))
for original_id in ['tanjiro-idle', 'tanjiro-walk']:
    original = next(j for j in jobs if j['id'] == original_id)
    revised = dict(original)
    revised['id'] = original_id + '-v2'
    if any(j['id'] == revised['id'] for j in jobs):
        continue
    revised['group'] = 'refinement'
    revised['prompt'] = 'output/imagegen/anime-v2/prompts/' + revised['id'] + '.txt'
    revised['out'] = 'output/imagegen/anime-v2/raw/' + revised['id'] + '.png'
    revised['references'] = original['references'] + ['output/imagegen/anime-v2/raw/tanjiro-stand_light.png']
    prompt = (ROOT / original['prompt']).read_text(encoding='utf-8')
    prompt += '''
CRITICAL CORRECTION: This is an alert COMBAT stance, NOT a casual standing/walking person.
His katana MUST already be UNSHEATHED, the long blade visibly held in BOTH hands in EVERY frame,
pointing diagonally forward RIGHT at chest height. Knees bent, feet apart, weight balanced low,
torso slightly leaned forward, determined focus toward opponent. The scabbard at hip is EMPTY.
Image 2 shows the attack animation style and fighting body language to connect to. Preserve image 1 identity.
No sword appearing/disappearing, no hands hanging loose, no hand on sheathed sword.
Keep even margins and an entirely visible sword tip in every frame. Maintain exactly the same
stance/proportions within the cycle; only natural breathing/cloth (idle) or footwork (walk) changes.
'''
    (ROOT / revised['prompt']).write_text(prompt, encoding='utf-8')
    jobs.append(revised)
for character in ['tanjiro', 'zenitsu']:
    original_id = character + '-crouch_heavy'
    original = next(j for j in jobs if j['id'] == original_id)
    revised = dict(original)
    revised['id'] = original_id + '-v2'
    if any(j['id'] == revised['id'] for j in jobs):
        continue
    revised['group'] = 'low-sweep-refinement'
    revised['prompt'] = 'output/imagegen/anime-v2/prompts/' + revised['id'] + '.txt'
    revised['out'] = 'output/imagegen/anime-v2/raw/' + revised['id'] + '.png'
    revised['references'] = original['references'] + ['output/imagegen/anime-v2/raw/' + character + '-guard_low.png']
    prompt = (ROOT / original['prompt']).read_text(encoding='utf-8')
    prompt += '''
MANDATORY LOW-STANCE CORRECTION. All SIX poses must remain deeply CROUCHING,
with deeply bent knees and hip low near the heels, just like reference image 2.
The top of the head MUST remain below 55 percent of a normal standing figure's height
in EVERY pose, including BOTH windup poses and BOTH recovery poses. Do not stand up.
The sword is already unsheathed and held firmly for a LOW HORIZONTAL SWEEP.
Frame 1: deep low guard. Frame 2: coil shoulders left with blade waist-low behind him.
Frame 3: begin ankle-height sweep right. Frame 4: fully extend blade RIGHT at ankle height.
Frame 5: low horizontal follow-through. Frame 6: return to deep crouched guard.
Never lift sword over the head. No overhead attack. No upright windup or upright recovery.
Keep the same anatomy, costume and physical body scale as the references; do not enlarge
the crouched body to fill each cell. Wide comfortable horizontal margins for whole blade.
Exactly six separate complete poses in a 3-column by 2-row grid, each facing RIGHT,
clean pure hot magenta background. No text, no ground, no effects. Normal human proportions.
'''
    (ROOT / revised['prompt']).write_text(prompt, encoding='utf-8')
    jobs.append(revised)
(OUT / 'jobs.json').write_text(json.dumps(jobs, ensure_ascii=False, indent=2), encoding='utf-8')
print('Registered targeted combat-stance refinements')
