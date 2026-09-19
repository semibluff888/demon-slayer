"""Create reproducible art briefs. All service calls use the installed imagegen CLI."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/anime-v2'
STYLE = '''Premium Japanese anime fighting game production art. Beautiful sophisticated hand-drawn anime,
precise dark ink contours, elegant normal human proportions (6.5 to 7 heads, NOT chibi),
two-tone cel shading, refined expressive faces, richly detailed but consistent costume.
Subtle cool moonlight rim from upper right, neutral soft key light. Colorful clear local colors.
No photorealism, no 3D, no text, numbers, labels, logos, watermark, UI or ground shadow.'''
IDENTITY = {
    'tanjiro': '''Tanjiro Kamado from Demon Slayer: recognizable burgundy spiky swept hair, forehead scar,
burgundy eyes, hanafuda earrings, green-and-black checkerboard haori over dark Demon Slayer uniform,
white belt, pale calf wraps and dark sandals. One black Nichirin katana, black scabbard at left hip.
Determined, compassionate youthful face. Keep checker squares the same scale in every frame.''',
    'zenitsu': '''Zenitsu Agatsuma from Demon Slayer: recognizable golden-yellow hair with orange tips,
choppy geometric bob, amber eyes, yellow-orange haori with small pale white triangular motifs,
dark Demon Slayer uniform, white belt, pale calf wraps and dark sandals. One Nichirin katana,
one scabbard at left hip. Focused calm youthful face. Keep triangle pattern scale consistent.'''
}
CLIPS = {
    'idle': (6, 3, 'A breathing idle LOOP in a ready guard, feet rooted. Six subtle consecutive moments of breathing and haori settling. No attacks.', True),
    'walk': (8, 4, 'Eight consecutive phases of ONE forward walking cycle to the right, alternating leg contact, passing and extension. Guarded torso. Same body scale; centered in each cell, no camera motion.', True),
    'walk_back': (8, 4, 'Eight consecutive phases of ONE defensive BACKSTEP cycle moving left while facing RIGHT. Alternating foot contacts, bent knees, sword guard toward the right. Center the body in every cell.', True),
    'crouch': (3, 3, 'Three consecutive poses: beginning to lower the body, halfway down, deep crouching ready stance facing right. Last pose must be clearly crouched with head at half standing height.', False),
    'jump': (6, 3, 'Six consecutive phases: takeoff crouch, upward leap, tucked airborne apex, descending with extended legs, landing crouch, upright recovery. No ground, no movement trails. Preserve the same body size.', False),
    'guard': (3, 3, 'Three consecutive standing defense poses: raise katana across upper torso, brace strongly against an incoming strike from right, hold firm guard. Clearly defensive, feet planted.', False),
    'guard_low': (3, 3, 'Three consecutive LOW crouching guard poses: lower stance, deeply crouched blocking sword forward, brace in low guard. Knees flexed; torso and head low; blade protects shins.', False),
    'hit': (4, 2, 'Four consecutive recoil poses when struck from the right: flinch, strong upper body recoil backward left, stagger and recover balance, return toward ready. No wounds or blood, keep feet level.', False),
    'knockdown': (5, 3, 'Five consecutive knockdown poses: stagger backward, lose balance, fall backward, contact ground, lie fully horizontal on the back with head to left and feet to right. Last pose is clearly prone, not standing. No drawn ground.', False),
    'throw': (6, 3, 'Six consecutive unarmed throwing motion keyframes facing right: reach forward with empty left hand, grasp an imaginary opponent, turn hip, pull and release rightward, follow-through, recover. Only this one character is drawn, no opponent. Sword remains safely in right hand or scabbard.', False),
    'victory': (6, 3, 'Six consecutive restrained victory poses: relax sword guard, lower katana, begin returning blade to scabbard, sheathe blade, lift head calmly, stand tall with haori settling. End in dignified calm victory.', False),
    'stand_light': (6, 3, 'Six consecutive quick standing horizontal katana cut poses: 1 ready, 2 small windup, 3 slash begins, 4 blade fully extended right at chest height, 5 follow-through, 6 recover guard. ONE slash, all frames chronologically distinct.', False),
    'stand_heavy': (6, 3, 'Six consecutive powerful standing diagonal katana cut poses: 1 windup, 2 sword raised over shoulder, 3 descending slash begins, 4 extended cutting contact toward right, 5 deep follow-through, 6 recover. ONE powerful slash.', False),
    'crouch_light': (6, 3, 'Six consecutive quick CROUCHING low katana cut poses: 1 crouch, 2 low windup, 3 slash forward, 4 blade extended right at knee height, 5 low follow-through, 6 recover crouching guard. Remain low throughout.', False),
    'crouch_heavy': (6, 3, 'Six consecutive deep low sweeping katana cut poses: 1 low ready, 2 coil backward, 3 sweep begins, 4 very low blade extended right at ankle height, 5 wide low follow-through, 6 recover low guard. Powerful sweep, deeply bent knees.', False),
    'air_light': (6, 3, 'Six consecutive AIRBORNE quick katana strike poses: 1 airborne ready, 2 windup, 3 short diagonal cut, 4 sword extended right-downward, 5 follow-through, 6 airborne recovery. Feet tucked or extended naturally in air. No floor.', False),
    'air_heavy': (6, 3, 'Six consecutive AIRBORNE heavy downward katana strike poses: 1 tucked airborne pose, 2 katana overhead, 3 forceful descending cut, 4 extended sword down-right, 5 strong follow-through, 6 landing anticipation. No floor.', False),
    'water_slash': (9, 3, 'Nine consecutive water surface slash keyframes: 1 ready, 2 rotate hips, 3 wind katana leftward, 4 sweep begins, 5 full horizontal cutting extension right, 6 follow-through across front, 7 sword decelerates, 8 recover feet, 9 ready. DO NOT draw water or effects; body and katana only.', False),
    'water_wheel': (9, 3, 'Nine consecutive forward somersaulting katana wheel keyframes: 1 crouch, 2 gather legs, 3 leap forward, 4 torso rotates head-first downward, 5 upside-down tuck with sword extended, 6 complete forward circle, 7 descending feet, 8 landing crouch, 9 recovery. Strong rotating body silhouettes. DO NOT draw water or effects.', False),
    'iai': (9, 3, 'Nine consecutive rapid iaido draw-cut keyframes: 1 calm low stance, 2 hand at sword hilt, 3 tense ready to draw, 4 draw katana, 5 diagonal cutting extension toward right, 6 follow-through, 7 blade returning, 8 sheathing, 9 low ready. No lightning or motion trails.', False),
    'thunder': (9, 3, 'Nine consecutive lightning-fast grounded dash attack keyframes: 1 low stance, 2 crouch hand on hilt, 3 deep coil, 4 launch with torso tilted almost horizontal toward right, 5 long low forward dash with katana extended, 6 low slash follow-through, 7 braking foot, 8 sheathe, 9 recover. No electricity or trails.', False),
}

def write_job(jobs, asset_id, group, prompt, size, references=None, metadata=None):
    prompt_path = OUT / 'prompts' / (asset_id + '.txt')
    prompt_path.parent.mkdir(parents=True, exist_ok=True)
    prompt_path.write_text(prompt.strip() + '\n', encoding='utf-8')
    jobs.append(dict(id=asset_id, group=group, prompt=str(prompt_path.relative_to(ROOT)),
                     out=str((OUT / 'raw' / (asset_id + '.png')).relative_to(ROOT)),
                     size=size, references=references or [], metadata=metadata or {}))

def main():
    if (OUT / 'jobs.json').exists():
        raise SystemExit('Production jobs already exist. Preserve refinements and request history; use a new version directory for a new brief.')
    jobs = []
    for character in IDENTITY:
        write_job(jobs, character + '-model', 'foundation',
                  'Use case: stylized-concept\nAsset: character model reference sheet.\n' + STYLE + '\n' + IDENTITY[character] + '''
Four full-body views across ONE row: front, 3/4 facing right, strict right side view, back.
Exactly the same person, outfit and proportions in all four views. Neutral standing guard.
Full hair, sandals, complete katana and scabbard in frame, generous margins between views.
Featureless SOLID HOT MAGENTA #ff00ff background. No shadows on background. No labels.''', '2048x1152')
    write_job(jobs, 'wisteria-master', 'foundation', '''Use case: stylized-concept
Asset: final hand-painted environment for a premium side-view anime sword fighting game, 16:9.
A breathtaking moonlit Japanese wisteria temple courtyard. Elegant detailed painted anime background,
rich architectural craft, soft atmospheric perspective, painterly textures, beautifully restrained lighting.
Pale full moon near (72% width, 24% height), indigo cloudy sky and distant mountain silhouettes.
Small elegant wooden temple with warm amber shoji windows in background center-left, stone lanterns at
far left and far right around 12% and 89% width. Lavender wisteria clusters frame UPPER corners only.
Horizontal wet stone fighting terrace covers bottom 23%; back edge/contact line EXACTLY at 79.5% image height.
No stairs or tall obstacles on fighting terrace. Straight horizontal foot-contact line, no tilted ground.
Center 65% is subdued in contrast, broad unobstructed open space for two fighters, lower half readable.
Subtle moon reflections on worn wet slate slabs, tiny fallen violet petals at edges. No people or animals.
Deep navy #101a32, violet #665278, moon silver, warm lantern amber. Not too dark. Crisp beautiful detail.
Full-bleed opaque background. No text, UI, frames, labels, watermark. No large foreground branches blocking center.
Camera exactly horizontal side-view at standing-person height, scene composed for a 2D fighting game.''', '2048x1152')
    for character in IDENTITY:
        ref = str((OUT / 'raw' / (character + '-model.png')).relative_to(ROOT))
        write_job(jobs, character + '-portrait', 'portraits',
                  'Use case: stylized-concept\nAsset: single hero portrait cutout for game menus.\n' + STYLE + '\n' + IDENTITY[character] + '''
Input image 1 is identity and costume reference ONLY. Create ONE magnificent full-body 3/4 hero portrait,
not a model sheet. Facing slightly LEFT toward the viewer, face visible and detailed, powerful composed
swordsman stance. Wind catches haori naturally, elegant flowing silhouette. Katana held diagonally down,
unobscured face; anatomically correct hands, one katana, one scabbard. Beautiful confident expression.
Standing person fills 86% of image height, face around x=50%, y=18%. Keep all hair, feet, sword in frame.
SOLID HOT MAGENTA #ff00ff featureless backdrop, no shadows, gradients, colored aura or other props.
Preserve the exact character identity and art style from the supplied reference.''', '1024x1536', [ref])
        for clip, (count, columns, poses, loop) in CLIPS.items():
            if (character == 'tanjiro' and clip in ('iai', 'thunder')) or (character == 'zenitsu' and clip.startswith('water_')):
                continue
            rows = (count + columns - 1) // columns
            # Cell width allows the katana to extend without touching a neighboring frame.
            width = 3072 if columns in (3, 4) else 2048
            height = rows * 768
            width = min(width, height * 3)
            prompt = ('Use case: stylized-concept\nAsset: production sprite animation contact sheet.\n' + STYLE + '\n' + IDENTITY[character] +
                      '\nInput image 1 is strict identity/costume/style reference, not the output layout.\n' +
                      'Draw EXACTLY {} full-body sequential animation frames, arranged {} columns by {} rows, chronological left to right then top to bottom.\n'.format(count, columns, rows) +
                      'Use an exact regular grid without drawn grid lines. Every cell has equal dimensions. Any unused final cell stays empty magenta.\n' +
                      'All frames face RIGHT, same camera and body scale. Standing figure is 500 pixels tall in a 768-pixel-high cell.\n' +
                      'Feet on a common baseline at 89% of cell height (except airborne and rotating poses). Center torso at 40% of cell width.\n' +
                      'Do not enlarge crouched or horizontal poses: they are the SAME person at the SAME scale.\n' +
                      'Keep the entire hair, costume, hands, blade and scabbard inside its cell with empty margins; no overlap between cells.\n' +
                      'Movement: ' + poses + '\n' +
                      'Each frame must be an actual successive pose with coherent anatomy and sword grip, never repeat identical drawings.\n' +
                      'Pure SOLID HOT MAGENTA #ff00ff across all empty background and gutters. No shadow, text, numbers, effects or extra characters.\n' +
                      'Preserve the supplied model identity, costume pattern, lighting and refined line art in EVERY drawing.')
            write_job(jobs, character + '-' + clip, 'animation-' + character, prompt,
                      '{}x{}'.format(width, height), [ref],
                      dict(character=character, clip=clip, count=count, columns=columns, rows=rows, loop=loop, fps=12))
    write_job(jobs, 'wisteria-sky', 'stage', '''Use case: stylized-concept
Input image 1 is the exact full composition reference. Create the clean distant background plate of this
SAME scene: remove ALL temple buildings, lanterns, terrace, wisteria and foreground, revealing continuous
indigo cloudy sky and distant mountain silhouettes behind them. Keep the moon at exactly the same position,
size, color, camera, painting style and horizon. The bottom may be dark distant forest. Full image opaque,
no transparency, no text, no people. This is the furthest parallax layer of the provided scene.''', '2048x1152',
              ['output/imagegen/anime-v2/raw/wisteria-master.png'])
    write_job(jobs, 'wisteria-canopy', 'stage', '''Use case: stylized-concept
Asset: two delicate hanging wisteria branches framing the upper corners of a wide game screen.
Input image 1 supplies the precise painted anime style and moonlight lighting. Draw lavender purple wisteria
clusters hanging from dark gracefully curved branches, concentrated left 27% and right 23% of the image.
Most of the center and all the lower 60% are empty SOLID HOT MAGENTA #ff00ff. Moonlit silver rims,
delicate petals, detailed but elegant, cohesive with the reference. No ground, moon, buildings, lettering.
Only the two upper corner branch arrangements on solid magenta, with sparse hanging bloom tips.''', '2048x1152',
              ['output/imagegen/anime-v2/raw/wisteria-master.png'])
    write_job(jobs, 'wisteria-foreground', 'stage', '''Use case: stylized-concept
Asset: subtle near foreground cutout for the SAME painted anime wisteria night garden in input image 1.
Only small tufts of cool dark grasses, a few fallen lavender petals, and a few low wet stones along the
BOTTOM LEFT and BOTTOM RIGHT corners. Details restricted to bottom 12% and outermost 25% of width.
Center and entire upper 85% are empty pure SOLID HOT MAGENTA #ff00ff. Moonlit rims, soft violet flowers.
No large object, floor plane, lettering, people, scene background, fog or shadows. Exquisite tiny detail.''', '2048x1152',
              ['output/imagegen/anime-v2/raw/wisteria-master.png'])
    fx = {
        'water-slash': 'A single powerful horizontal crescent slash of blue water flowing LEFT to RIGHT. Sweeping arc, dark navy ink edges, turquoise body, gorgeous white curling foam and suspended droplets. Long thin dynamic silhouette with open center.',
        'water-wheel': 'A single nearly complete circular ring of turbulent blue water, viewed perfectly from the side. Open center, dark navy ink outlines, turquoise water, exquisite white curling wave crests, droplets following circle. Perfectly readable circular wheel silhouette.',
        'thunder': 'A long horizontal sharp golden lightning burst, flowing LEFT to RIGHT with a bright white-hot central cutting line, many fine branching golden electric arcs and small glowing sparks. Dynamic thin lightning spear, dramatic elegant jagged silhouette.',
        'impact': 'A single exquisite anime sword contact burst with a small white-hot star-shaped center and elegant long ivory-gold rays, fine flying sparks and a restrained circular shockwave. Crisp clean inked shapes, strong central star silhouette.'
    }
    for name, subject in fx.items():
        write_job(jobs, 'fx-' + name, 'effects', 'Use case: stylized-concept\nAsset: isolated hand-drawn anime combat VFX texture.\n' + subject + '''
Premium theatrical anime effects animation artwork, confident calligraphic ink contours, cel shaded color,
visually intricate but readable, full effect within frame with generous empty margins. No character,
no sword, no lettering, no UI, no ground. SOLID BLACK #000000 background for additive compositing.
No rectangular haze or background texture; all four edges fade to completely pure black.''',
                  '1536x1024' if name != 'water-wheel' else '1024x1024')
    (OUT / 'raw').mkdir(parents=True, exist_ok=True)
    (OUT / 'records').mkdir(parents=True, exist_ok=True)
    (OUT / 'jobs.json').write_text(json.dumps(jobs, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Prepared {} jobs in {}'.format(len(jobs), OUT))

if __name__ == '__main__':
    main()
