"""Temporarily install processed v3 clips into the shipped atlases for in-engine review.

Reads output/imagegen/<id>-v3/imports/<clip>/frame-NN.png (1024x640 canvases written
by process.py), packs them into art/characters/<id>/v3-preview.png (and the awakening
copy) and points those clips at it; the idle clip gets "cycle": true. Other clips,
timing data and phase breaks are untouched. Undo with --restore (git checkout of the
two atlas files plus removal of the preview pages). The final atlas comes from pack.py.

Usage: python tools/art_v3/preview.py --clips idle,walk,stand_light,water_slash
       python tools/art_v3/preview.py --restore
"""
import argparse
import json
import subprocess

from PIL import Image

from common import ROOT, production

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
    sprites = []
    for clip in args.clips.split(','):
        for path in sorted((production(args.character) / 'imports' / clip).glob('frame-*.png')):
            image = Image.open(path).convert('RGBA')
            box = image.getbbox()
            sprites.append((clip, image.crop(box), box[:2]))
    width = 4096
    x = y = 2
    row = 0
    placed = []
    for clip, image, offset in sprites:
        if x + image.width + 2 > width:
            x, y, row = 2, y + row + 4, 0
        placed.append((clip, image, offset, (x, y)))
        x += image.width + 4
        row = max(row, image.height)
    page = Image.new('RGBA', (width, y + row + 2))
    clips = {}
    for clip, image, offset, at in placed:
        page.alpha_composite(image, at)
        clips.setdefault(clip, []).append(dict(texture=PAGE, region=[at[0], at[1], image.width, image.height], offset=list(offset)))
    folder = ROOT / 'art/characters' / args.character
    for target in (folder, folder / 'awakening'):
        page.save(target / PAGE)
        atlas_path = target / 'atlas.json'
        atlas = json.loads(atlas_path.read_text(encoding='utf-8'))
        for clip, frames in clips.items():
            entry = atlas['clips'][clip]
            if clip != 'idle' and len(entry['frames']) != len(frames):
                raise SystemExit('%s: frame count %d differs from atlas %d' % (clip, len(frames), len(entry['frames'])))
            entry['frames'] = frames
            if clip == 'idle':
                entry.update(loop=True, fps=10, cycle=True)
        atlas_path.write_text(json.dumps(atlas, ensure_ascii=False, indent=2), encoding='utf-8')
    print('preview installed:', {clip: len(frames) for clip, frames in clips.items()})


if __name__ == '__main__':
    main()
