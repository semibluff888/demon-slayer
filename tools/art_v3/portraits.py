"""Portraits from the v3 canon: the HUD bust (also the MAX cut-in), the character-select
full body, the awakened HUD bust and the menu avatar.

prepare  adds the generation jobs to output/imagegen/<id>-v3/jobs.json (group
         "portraits", two attempts per drawing; run them with run.py --group portraits).
build    imports the chosen drawings into art/characters/<id>/:
           battle-portrait.png    1024x1024 bust; SuperView crops FACE_REGION for the cut-in
           avatar.png             192x192, the established thumbnail crop on the card colour
           awakening/portrait.png 512x512, the bust through awaken.py like every sprite frame
           portrait.png           the full body with a 12 px margin (the select screen shows
                                  the top 74%)
         and records sources and hashes in output/imagegen/<id>-v3/portraits.json.

Usage: python tools/art_v3/portraits.py prepare --character zenitsu
       python tools/art_v3/portraits.py build --character zenitsu --bust 1 --full 2
"""
import argparse

import numpy as np
from PIL import Image

from common import ROOT, cutout, production, read, rel, save, sha256, spec
import anatomy
import awaken

RESAMPLE = Image.Resampling.LANCZOS
# The previous busts put the hair top ~30 px down and the head centre at ~46% width.
BUST_TOP = 30
BUST_HEAD_X = 0.47

BUST_PROMPT = """Use case: identity-preserve
Asset type: premium hand-inked anime fighting-game HUD portrait and MAX super cut-in (one bust illustration), {name}.
Input image 1: APPROVED MODEL SHEET. Exact identity, costume construction and colours.
Input image 2: APPROVED IDLE POSE. Exact line weight, rendering and colours of the in-game sprites.
Input image 3: OLD PORTRAIT. Framing reference only (head and shoulders filling a square); its colours and face are outdated, follow input images 1 and 2.
Primary request: ONE bust portrait in three-quarter view, head and shoulders turned and looking slightly to the RIGHT toward an off-screen opponent. The head is large in the frame: the face in the upper middle, the chin at about 60 percent of the image height, the shoulders and the top of the {garment} filling the bottom edge. ALL of the hair stays inside the image with a 6 percent margin at the top and both sides.
Expression: {expression}
Identity: {identity}
Rendering: {style} Detailed hair locks, a clean luminous face, the same colours as input image 1.
Constraints: no text, no frame, no effects (no {effects}), {bust_rule}. Pure solid {background} background everywhere.
"""

FULL_PROMPT = """Use case: identity-preserve
Asset type: premium anime fighting-game character-select key art (one full-body illustration), {name}.
Input image 1: APPROVED MODEL SHEET. Exact identity, costume construction, colours and {heads}-head proportions.
Input image 2: APPROVED IDLE POSE. Exact line weight, rendering and colours of the in-game sprites.
Input image 3: OLD SELECT PORTRAIT. Composition reference only (one tall full-body figure filling the frame); its colours, eyes and pose are outdated, follow input images 1 and 2.
Primary request: ONE full-body figure in three-quarter view, body and face turned to the RIGHT toward an off-screen opponent. {pose}
Framing: the figure fills the image height from the top of the hair to the soles with a 3 percent margin; the whole figure, {inside} stay inside the image. Normal adult proportions, never chibi.
Expression: {expression}
{weapon_label}: {katana}
Identity: {identity}
Rendering: {style} Detailed hair locks and fabric folds, the same colours as input image 1.
Constraints: no text, no frame, no floor, no shadow, no effects (no {effects}). Pure solid {background} background everywhere.
"""

# Per character: what the portraits show and the avatar card colour.
CHARACTERS = {
    'zenitsu': dict(
        expression=('he fights asleep: eyes CLOSED with calm curved lids, eyebrows relaxed, mouth a small closed line; serene and '
                    'focused, never frightened or comic.'),
        pose=('He stands in a compact Thunder Breathing iai stance: feet apart, knees slightly bent, torso leaning a little forward, '
              'his left hand holding the SHEATHED katana at his left hip and his right hand on the hilt in front of his belly, ready '
              'to draw. The haori flares slightly behind him.'),
        katana=('ONE katana, SHEATHED on his left hip: the white scabbard with its gold tip points BACKWARD (to the LEFT, behind '
                'his hip), the white-and-gold hilt with its round gold guard points FORWARD (to the RIGHT) in front of his belly.'),
        avatar_background='#403326',
    ),
    'akaza': dict(
        expression=('a confident, cruel grin that shows his teeth; golden-yellow eyes with small dark pupils (no writing in the eyes) '
                    'fixed on the opponent; fearless and eager for the fight.'),
        pose=('He stands in his brawler guard exactly as in input image 2: feet wide apart, knees bent, torso leaning slightly forward, '
              'both navy hands raised in front of his chest as half-closed claws, elbows out; the navy sash ends hang in front of the '
              'white trousers.'),
        katana=('he is UNARMED: no sword, no scabbard and no weapon of any kind; both hands are bare, entirely navy-blue (the tattoo '
                'covers them) with red fingernails.'),
        weapon_label='Hands', garment='magenta vest', bust_rule='no weapon, no hands in front of the face',
        inside='both hands and the sash ends', heads=7,
        # The idle key with the slightly stronger upper body (checkpoint 4 review).
        key='output/imagegen/akaza-v3/references/approved-idle-key-v2.png',
        avatar_background='#15374a',
    ),
}
# Template words that differ per character; the defaults are Zenitsu's (and Tanjiro's) original text.
DEFAULTS = dict(weapon_label='Katana', garment='haori', bust_rule='no sword in front of the face', inside='the haori and the katana')


def prepare(args):
    data = spec(args.character)
    extra = CHARACTERS[args.character]
    out = production(args.character)
    jobs = read(out / 'jobs.json', [])
    known = {job['id'] for job in jobs}
    references = ['output/imagegen/%s-v3/raw/%s-v3-model.png' % (args.character, args.character),
                  extra.get('key', 'output/imagegen/%s-v3/references/approved-idle-candidate.png' % args.character)]
    fields = dict(DEFAULTS, name=data['name'], identity=data['identity'], style=data['style'], background=data['background_name'],
                  effects=data['prompt']['effects'], heads=data['canon'].get('heads', 6.5))
    fields.update({k: v for k, v in extra.items() if k not in ('key', 'avatar_background')})
    added = 0
    for kind, template, size, old in [('bust', BUST_PROMPT, '1024x1024', 'battle-portrait.png'),
                                      ('full', FULL_PROMPT, '1024x1536', 'portrait.png')]:
        reference = out / 'references' / ('old-' + old)
        if not reference.exists():
            Image.open(ROOT / 'art/characters' / args.character / old).save(reference)
        for attempt in (1, 2):
            job_id = '%s-v3-portrait-%s-%d' % (args.character, kind, attempt)
            if job_id in known:
                continue
            prompt = out / 'prompts' / (job_id + '.txt')
            prompt.write_text(template.format(**fields), encoding='utf-8')
            jobs.append(dict(id=job_id, group='portraits', prompt=rel(prompt), out=rel(out / 'raw' / (job_id + '.png')), size=size,
                             references=references + [rel(reference)], metadata=dict(character=args.character, kind=kind, attempt=attempt)))
            added += 1
    save(out / 'jobs.json', jobs)
    print('Added', added, 'portrait jobs')


def figure(path, data=None):
    """The drawing cut out of its background and cropped to the figure."""
    image = cutout(Image.open(path), data)
    return image.crop(image.getbbox())


def build(args):
    out = production(args.character)
    target = ROOT / 'art/characters' / args.character
    data = anatomy.configure(args.character)
    record = dict(character=args.character, files={})
    bust_source = out / 'raw' / ('%s-v3-portrait-bust-%d.png' % (args.character, args.bust))
    full_source = out / 'raw' / ('%s-v3-portrait-full-%d.png' % (args.character, args.full))
    # HUD bust framed like the previous portraits: the hair top BUST_TOP px below the top
    # edge, the shoulders on the bottom edge (wider shoulders are cropped), the head box
    # centred at BUST_HEAD_X, so the cut-in's FACE_REGION keeps the whole face.
    bust = figure(bust_source, data)
    bust = bust.resize((round(bust.width * (1024 - BUST_TOP) / bust.height), 1024 - BUST_TOP), RESAMPLE)
    head = anatomy.head(np.asarray(bust))
    centre = (head['box'][0] + head['box'][2]) / 2 if head else bust.width / 2
    canvas = Image.new('RGBA', (1024, 1024))
    canvas.alpha_composite(bust, (round(1024 * BUST_HEAD_X - centre), BUST_TOP))
    canvas.save(target / 'battle-portrait.png')
    thumbnail = canvas.crop((32, 0, 992, 960)).resize((192, 192), RESAMPLE)
    avatar = Image.new('RGBA', (192, 192), CHARACTERS[args.character]['avatar_background'])
    avatar.alpha_composite(thumbnail)
    avatar.save(target / 'avatar.png')
    # Awakened bust: the same derivation as the awakened sprites (spec "awakening").
    small = np.asarray(canvas.resize((512, 512), RESAMPLE))
    awakened, changed = awaken.bake(small.copy())
    Image.fromarray(awakened, 'RGBA').save(target / 'awakening/portrait.png')
    # Select-screen full body with the previous portraits' 12 px margin.
    full = figure(full_source, data)
    sheet = Image.new('RGBA', (full.width + 24, full.height + 24))
    sheet.alpha_composite(full, (12, 12))
    sheet.save(target / 'portrait.png')
    for name, source in [('battle-portrait.png', bust_source), ('avatar.png', bust_source), ('awakening/portrait.png', bust_source),
                         ('portrait.png', full_source)]:
        record['files'][name] = dict(source=rel(source), source_sha256=sha256(source), sha256=sha256(target / name))
    record['awakened_changed_pixels'] = changed
    save(out / 'portraits.json', record)
    print('Imported portraits for', args.character, '- awakened bust changed', changed, 'pixels; full body', sheet.size)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('command', choices=['prepare', 'build'])
    parser.add_argument('--character', default='zenitsu')
    parser.add_argument('--bust', type=int, default=1)
    parser.add_argument('--full', type=int, default=1)
    args = parser.parse_args()
    prepare(args) if args.command == 'prepare' else build(args)


if __name__ == '__main__':
    main()
