"""Prepare Nezuko's authorized v6 action redraws using the existing CPA queue."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/awakening-v6'
MODEL = 'output/imagegen/awakening-v6-preview/raw/nezuko-idle-v6.png'

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def main():
    for folder in ['prompts', 'raw', 'records', 'imports', 'review', 'baseline']:
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    (OUT / '.gdignore').write_text('', encoding='utf-8')
    original_jobs = json.loads((ROOT / 'output/imagegen/awakening-v2/jobs.json').read_text(encoding='utf-8-sig'))
    jobs = []
    for old in original_jobs:
        if old['metadata']['character'] != 'nezuko':
            continue
        job = copy.deepcopy(old)
        meta = job['metadata']
        clip = meta['clip']
        count, cols, rows = meta['count'], meta['columns'], meta['rows']
        if clip == 'idle':
            direction = f'Draw EXACTLY {count} subtle breathing-loop frames. Match the feet, body facing and head direction of image 1, but BOTH ARMS HANG NATURALLY DOWN at the sides with relaxed open hands as in image 2. No raised fists, hands on the obi, or defensive guard. A stable calm fierce idle stance; only subtle breathing and hair motion. Preserve foot placement across the loop.'
        elif clip == 'awakening_start':
            direction = 'Draw EXACTLY 6 chronological awakening activation frames: gather strength, tense, lift chin, release power, settle, ready. The last two frames settle into BOTH ARMS LOWERED naturally beside the body, matching image 2. Fixed feet and consistent body scale. No screaming. The demon form is present in every frame.'
        else:
            direction = f'Redraw EXACTLY {count} chronological poses from image 1. Preserve its action, limb positions, facing, gesture, frame order, ground contact, and root motion. These are {clip} animation frames, not repeated standing poses. Apply the identity and costume of image 2 to every drawing, including upside-down or recoiling frames.'
        prompt = f'''Use case: style-transfer
Asset type: final production anime fighting-game animation sprite sheet: Nezuko awakening / {clip}.
Image 1 is the exact action, facing and grid-layout reference. Its old costume and face are NOT the appearance target.
Image 2 is the final revised character-design master. Closely preserve this face, single ivory horn, long dark hair with orange ends, pink slit pupils, pink ribbon, branching temple veins, leafy vine markings, costume silhouette, colors and rendering style.
{direction}
Costume and identity: one pronounced ridged horn on anatomical right forehead; no bamboo, no muzzle strap, no extra horn. Pink hemp-leaf kimono with red-white checkered obi and green/gold cords. Dark cocoa haori with intact shoulder tops, battle-worn sleeve ends and lower hem. Wider shallow collar reveals collarbones only; chest stays covered by overlapping opaque cloth, no cleavage or breast emphasis. Same natural proportions and recognizable age as the master, neutral nonsexual combat presentation. Asymmetric skirt and visible legs with vine markings; NO added long trousers or leggings. Keep opaque overlapping fabric over the pelvis and upper thighs through all kicks, rolls, jumps and falls, no underwear visible. Dark calf wraps and sandals. Fingers, toes, knees and elbows anatomically coherent.
Match image 2's polished theatrical anime linework, rich restrained colors, crisp layered hair, expressive face, and clean coherent cel shading. Preserve the master's facial identity and tall athletic silhouette in EVERY frame; do not revert to the ordinary childlike sprite face or old outfit during guard, hit, knockdown, throws or MAX.
Layout: {cols} equal columns by {rows} equal rows, chronological row-major order, EXACTLY {count} complete separate figures. Every figure centered in its own cell with generous clean gutters. Same anatomical scale throughout; crouched, rolling and horizontal bodies must not be enlarged to fill their cells. Complete horn, hair, fingers and sandals inside each cell. Leave unused cells completely empty. No opponents or duplicate limbs.
Absolutely flat bright CYAN #00ffff background and gutters for offline alpha extraction, or genuine transparent alpha. No floor, shadows, glow, blood-fire, particles, painted aura, captions, numbers, grids, borders, watermarks or other objects. Existing game VFX are rendered separately.
'''
        pp = OUT / 'prompts' / (job['id'] + '.txt')
        pp.write_text(prompt, encoding='utf-8')
        job['out'] = (OUT / 'raw' / (job['id'] + '.png')).relative_to(ROOT).as_posix()
        job['prompt'] = pp.relative_to(ROOT).as_posix()
        job['references'] = [old['references'][0], MODEL]
        job['group'] = 'pilot-actions' if clip in ['idle', 'awakening_start'] else 'awakening'
        job['metadata']['registration_profile'] = 'v2'
        jobs.append(job)
    save(OUT / 'jobs.json', jobs)
    portrait_prompt = OUT / 'prompts/nezuko-portrait.txt'
    portrait_prompt.write_text('''Use case: identity-preserve
Asset type: premium anime fighting-game awakened HUD portrait, square head-and-shoulders artwork.
Input image 1 is the final Nezuko awakened design master. Preserve exactly its facial identity, single ridged ivory horn on anatomical RIGHT forehead, pink eyes, branching temple veins, hairline, long black-orange hair, ribbon, and fierce closed-mouth expression.
Draw the head and upper shoulders in three-quarter view facing screen RIGHT, close but with the full horn and hair silhouette inside the square. Face dominates the composition and remains readable at 88 pixels. Dark plum background with a restrained pink glow; clean cel shading and detailed ink drawing match the master. Normal recognizable age and natural anatomy. The shoulders have intact cocoa haori fabric and the chest is covered by opaque overlapping kimono; no cleavage, no torso emphasis. No bamboo, muzzle strap, extra horn, text, logo, watermark, decorative frame or other character.
''', encoding='utf-8')
    save(OUT / 'static.json', [dict(id='nezuko-portrait', group='portraits', out=(OUT/'raw/nezuko-portrait.png').relative_to(ROOT).as_posix(), prompt=portrait_prompt.relative_to(ROOT).as_posix(), references=[MODEL], size='1024x1024', model='gpt-image-2', metadata=dict(character='nezuko', purpose='authorized awakened HUD portrait'))])
    preserved_path = OUT / 'preserved-runtime.json'
    if not preserved_path.exists():
        preserved = {}
        for path in sorted((ROOT/'art/characters').rglob('*')):
            if not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            if relative.startswith('art/characters/nezuko/awakening/') and (path.name.startswith('atlas') or path.name.startswith('portrait.png')):
                continue
            preserved[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        save(preserved_path, preserved)
        (OUT/'baseline/nezuko-atlas.json').write_bytes((ROOT/'art/characters/nezuko/awakening/atlas.json').read_bytes())
        (OUT/'baseline/nezuko-portrait.png').write_bytes((ROOT/'art/characters/nezuko/awakening/portrait.png').read_bytes())
    save(OUT/'authorization.json', dict(integration_authorized=True, approval_gate_waived=True, character='nezuko', source_model=MODEL, scope='Repair shoulder fabric, generate and integrate full alternate combat animations and portrait; preserve ordinary form and other characters.', evidence='User explicitly instructed to integrate after this revision without asking for another confirmation.'))
    print('Prepared',len(jobs),'action sheets,',sum(j['metadata']['count'] for j in jobs),'frames and one portrait.')

if __name__ == '__main__':
    main()
