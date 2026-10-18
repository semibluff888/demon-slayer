"""Temporarily install processed v3 clips into the shipped atlases for in-engine review.

Reads output/imagegen/<id>-v3/imports/<clip>/frame-NN.png (1024x640 canvases written
by process.py), packs them into art/characters/<id>/v3-preview.png and points those
clips at it. The awakening atlas gets its own page, derived per frame exactly as
pack.py will (awaken.py: Tanjiro's forehead mark, Zenitsu's Godspeed grade); a character
whose spec "awakening" mode is "keep" (Nezuko: the shipped demon form stays) leaves the
awakening atlas alone. The idle
clip gets "cycle": true; a clip the atlas does not have yet takes its timing from the
pose script ("new"); clips marked "mirror" are flipped like pack.py does. Other clips,
timing data and phase breaks are untouched. Undo with --restore (git checkout of the
two atlas files plus removal of the preview pages). The final atlas comes from pack.py.

Usage: python tools/art_v3/preview.py --character zenitsu --clips idle,walk,stand_light,thunder
       python tools/art_v3/preview.py --character zenitsu --restore
"""
import argparse
import json
import subprocess

import numpy as np
from PIL import Image

from common import POSES, ROOT, production, read
import anatomy
import awaken
import pack

PAGE = 'v3-preview.png'


def restore(character):
    folder = ROOT / 'art/characters' / character
    subprocess.run(['git', 'checkout', '--', 'art/characters/%s/atlas.json' % character,
                    'art/characters/%s/awakening/atlas.json' % character], cwd=ROOT, check=True)
    for path in list(folder.glob(PAGE + '*')) + list((folder / 'awakening').glob(PAGE + '*')):
        path.unlink()
    print('restored', character)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', default='tanjiro')
    parser.add_argument('--clips')
    parser.add_argument('--restore', action='store_true')
    args = parser.parse_args()
    if args.restore:
        restore(args.character)
        return
    anatomy.configure(args.character)
    poses = read(POSES / (args.character + '.json'))['clips']
    keep = awaken.settings().get('mode') == 'keep'
    sprites = []
    for clip in args.clips.split(','):
        flip = poses.get(clip, {}).get('mirror')
        for path in sorted((production(args.character) / 'imports' / clip).glob('frame-*.png')):
            image = Image.open(path).convert('RGBA')
            awake = image if keep else Image.fromarray(awaken.bake(np.asarray(image))[0], 'RGBA')
            if flip:
                image, awake = pack.mirrored(image), pack.mirrored(awake)
            box = image.getbbox()
            sprites.append((clip, image.crop(box), awake.crop(box), box[:2]))
    width = 4096
    x = y = 2
    row = 0
    placed = []
    for clip, image, awake, offset in sprites:
        if x + image.width + 2 > width:
            x, y, row = 2, y + row + 4, 0
        placed.append((clip, image, awake, offset, (x, y)))
        x += image.width + 4
        row = max(row, image.height)
    pages = [Image.new('RGBA', (width, y + row + 2)), Image.new('RGBA', (width, y + row + 2))]
    clips = {}
    for clip, image, awake, offset, at in placed:
        pages[0].alpha_composite(image, at)
        pages[1].alpha_composite(awake, at)
        clips.setdefault(clip, []).append(dict(texture=PAGE, region=[at[0], at[1], image.width, image.height], offset=list(offset)))
    folder = ROOT / 'art/characters' / args.character
    for target, page in ((folder, pages[0]),) + (() if keep else ((folder / 'awakening', pages[1]),)):
        page.save(target / PAGE)
        atlas_path = target / 'atlas.json'
        atlas = json.loads(atlas_path.read_text(encoding='utf-8'))
        stance = anatomy.profile().get('qa', {}).get('idle_vs_upright')
        if stance and 'idle' in clips:
            atlas['idle_vs_upright'] = stance
        for clip, frames in clips.items():
            if clip not in atlas['clips']:
                atlas['clips'][clip] = pack.clip_metadata(clip, len(frames), {}, poses)
            entry = atlas['clips'][clip]
            if clip != 'idle' and entry.get('frames') and len(entry['frames']) != len(frames):
                raise SystemExit('%s: frame count %d differs from atlas %d' % (clip, len(frames), len(entry['frames'])))
            entry['frames'] = frames
            if clip == 'idle':
                entry.update(loop=True, fps=10, cycle=True)
        atlas_path.write_text(json.dumps(atlas, ensure_ascii=False, indent=2), encoding='utf-8')
    print('preview installed:', {clip: len(frames) for clip, frames in clips.items()})


if __name__ == '__main__':
    main()
