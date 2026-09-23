"""Append versioned combat-polish sources to the established CPA job queue."""
import json
from pathlib import Path
from prepare_art_production import STYLE, IDENTITY, write_job

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/anime-v2'


def main():
    jobs = json.loads((OUT / 'jobs.json').read_text(encoding='utf-8-sig'))
    additions = []
    write_job(additions, 'tanjiro-water_wheel-polish-v1', 'combat-polish',
        'Use case: stylized-concept\nAsset: production character animation sheet.\n' + STYLE + '\n' + IDENTITY['tanjiro'] + """
Reference 1 defines the exact character identity and costume. Reference 2 defines the established drawing style and anatomy. Create a NEW sword BACKFLIP animation.
EXACTLY TWELVE distinct chronological full-body drawings, FOUR columns by THREE rows. Equal cells, no visible grid or labels. Side view; starts and finishes facing RIGHT. Consistent anatomical proportions including inverted poses. One black katana firmly held in BOTH HANDS during the cutting rotation, one scabbard at left hip. All hair, hands, blade, feet and cloth inside each cell with generous gaps.
One elegant backward somersault with a rising overhead sword wheel. The body rotates BACKWARD: head initially travels LEFT, tucked feet travel upward RIGHT. NOT a forward roll or cartwheel. Sword stays outside the body, never crosses torso or knees. Each successive pose rotates smoothly about the pelvis; do not rotate a single rigid drawing.
Frames 1-3 PREPARATION: 1 low guarded crouch; 2 compress knees and lower katana ahead RIGHT; 3 push off and arch shoulders backward LEFT with sword beginning to rise in FRONT.
Frames 4-8 CUTTING BACKFLIP: 4 lean diagonally back, head upper LEFT and knees ahead RIGHT; 5 near horizontal, head LEFT and tucked knees RIGHT above hips, blade sweeping forward-up; 6 fully inverted, pelvis above head, compact tucked knees, sword outside body; 7 continue backward rotation, head RIGHT and legs LEFT, opening tuck; 8 upright facing RIGHT, legs extending down, blade completes front vertical circle.
Frames 9-12 RECOVERY: 9 feet land, knees flexed, sword diagonally forward RIGHT; 10 absorb landing in balanced low stance; 11 raise torso and settle haori; 12 familiar ready guard facing RIGHT.
Refined natural 6.5-7 head anatomy. Flowing haori follows angular momentum. Continuous sword grip. Preserve head size, limb length and checker pattern scale. Pelvis centered horizontally in each cell; grounded feet near 90 percent cell height, standing anatomy about 68 percent cell height. Rotating bodies centered with room above and below.
Pure SOLID HOT MAGENTA #ff00ff background and gutters, no magenta reflections. No water, aura, trails, clones, ground, shadows, text, numbers or extra characters. Water is rendered separately.
""", '2048x1536',
        ['output/imagegen/anime-v2/raw/tanjiro-model.png', 'output/imagegen/anime-v2/raw/tanjiro-idle-v2.png'],
        dict(character='tanjiro', clip='water_wheel', count=12, columns=4, rows=3,
             loop=False, fps=18, anchor_mode='pelvis', root_fraction=0.5, phase_breaks=[3, 8]))
    common = """
Reference supplies only blue water, white curling foam and intricate fluid detail. NEW isolated game VFX sprite: crisp dark navy contours, substantial turquoise water body, bright white curling foam, readable at small size. Graceful theatrical anime water with a few separate droplets. No haze rectangle, text, UI, character, sword, ground or scenery. Pure solid HOT MAGENTA #ff00ff background, no magenta reflections. Complete effect inside generous margins. Never copy the reference's full ring.
"""
    write_job(additions, 'fx-water-slash-projectile-polish-v1', 'combat-polish',
        'Use case: stylized-concept\nAsset: compact VERTICAL water crescent projectile moving RIGHT.\n' + common + """
Tall crescent shaped like a RIGHT parenthesis ")": thick convex cutting front on RIGHT, open concave center on LEFT, upper and lower tips curling backward LEFT. Visible width:height is 2:3. Thick central leading crest, tapered tips, flowing blue interior and WHITE breaking surf along the forward edge. Force moves horizontally RIGHT, with 3-5 tiny trailing droplets LEFT inside the silhouette envelope. ONE compact wave blade, no horizontal ellipse, wheel, sprawling splash or long wake.
""", '1024x1536', ['art/effects/water-wheel-body.png'],
        dict(kind='effect', effect='water-slash-projectile', matte='magenta', aspect=[2, 3]))
    write_job(additions, 'fx-water-slash-spray-polish-v1', 'combat-polish',
        'Use case: stylized-concept\nAsset: short blue-white water spray at sword projectile launch.\n' + common + """
ONE compact fan of three curling splashes shooting from lower LEFT toward upper RIGHT, width:height 3:2. Turquoise base opens into three thin WHITE foam tongues and 4-6 small droplets. Delicate spray, strongest at origin, pointed dissolving tips. No ring, closed ellipse or large water wall. Small launch accent paired with a separate projectile.
""", '1536x1024', ['art/effects/water-wheel-body.png'],
        dict(kind='effect', effect='water-slash-spray', matte='magenta', aspect=[3, 2]))
    known = {job['id'] for job in jobs}
    jobs.extend(job for job in additions if job['id'] not in known)
    (OUT / 'jobs.json').write_text(json.dumps(jobs, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Prepared three versioned combat-polish jobs; existing sources retained.')


if __name__ == '__main__':
    main()
