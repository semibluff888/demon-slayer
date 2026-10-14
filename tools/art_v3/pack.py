"""Pack processed v3 frames into the shipped atlases.

Writes art/characters/<id>/atlas.json + atlas-N.png (combat clips), round-atlas.json +
round-N.png (round intro/victory/defeat) and awakening/atlas.json + atlas-N.png (every
clip with the forehead mark baked by awaken.py, identical geometry). Existing clips
keep their timing metadata (fps, loop, phase_breaks, segment_sync, timeline, anchor
mode) from the previous atlases; new clips take theirs from the pose script; idle
becomes the authored 12-frame loop ("cycle": true). Stale pages are removed.
Clips marked "mirror" in the pose script are drawn facing right like every sheet but
ship flipped around the feet anchor: a throw victim is drawn with its thrower's
facing, so its art faces left (toward the thrower), as in every other atlas.

Usage: python tools/art_v3/pack.py [--character tanjiro]
"""
import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from common import ROOT, POSES, production, read, rel, save, sha256, spec
import awaken

PAGE = 2048
ANCHOR_X = 448
ROUND = ('round_intro', 'round_victory', 'round_defeat')


def previous(character, path):
    """Atlas metadata as committed (the working copy may hold a preview)."""
    text = subprocess.run(['git', 'show', 'HEAD:art/characters/%s/%s' % (character, path)], cwd=ROOT,
                          capture_output=True, text=True, encoding='utf-8').stdout
    return json.loads(text) if text else {'clips': {}}


def mirrored(image):
    """The canvas frame flipped around the feet anchor column."""
    right = image.getbbox()[2]
    if right > 2 * ANCHOR_X:
        raise SystemExit('mirrored frame would leave the canvas (right edge %d)' % right)
    canvas = Image.new('RGBA', image.size)
    canvas.paste(ImageOps.mirror(image), (2 * ANCHOR_X - image.width, 0))
    return canvas


def frames_of(character, clip):
    folder = production(character) / 'imports' / clip
    return [Image.open(path).convert('RGBA') for path in sorted(folder.glob('frame-*.png'))]


def pack(images, folder, prefix):
    """Shelf-pack trimmed drawings into PAGE x PAGE sheets; returns entries per (clip, index)."""
    sprites = []
    for (clip, index), image in images.items():
        box = image.getbbox()
        sprites.append((clip, index, image.crop(box), box[:2]))
    sprites.sort(key=lambda item: item[2].height, reverse=True)
    entries = {}
    pages = []
    page = Image.new('RGBA', (PAGE, PAGE))
    x = y = 2
    row = 0
    for clip, index, image, offset in sprites:
        if x + image.width + 2 > PAGE:
            x, y, row = 2, y + row + 4, 0
        if y + image.height + 2 > PAGE:
            pages.append(page)
            page = Image.new('RGBA', (PAGE, PAGE))
            x = y = 2
            row = 0
        page.alpha_composite(image, (x, y))
        entries[(clip, index)] = dict(texture='%s-%d.png' % (prefix, len(pages)), region=[x, y, image.width, image.height], offset=list(offset))
        x += image.width + 4
        row = max(row, image.height)
    pages.append(page)
    folder.mkdir(parents=True, exist_ok=True)
    # Pages beyond the new count go away with their import settings; pages that are
    # rewritten keep their .import sidecar (compression and mipmap settings).
    keep = {'%s-%d.png' % (prefix, number) for number in range(len(pages))}
    for stale in folder.glob(prefix + '-*.png'):
        if stale.name not in keep:
            stale.unlink()
            sidecar = stale.with_name(stale.name + '.import')
            if sidecar.exists():
                sidecar.unlink()
    for number, image in enumerate(pages):
        temporary = folder / ('%s-%d.building.png' % (prefix, number))
        image.save(temporary)
        temporary.replace(folder / ('%s-%d.png' % (prefix, number)))
    return entries, len(pages)


def clip_metadata(name, count, old, poses):
    if name == 'idle':
        return dict(loop=True, fps=10, cycle=True, phase_breaks=[4, 8], segment_sync=False, anchor_mode='feet', timeline=[])
    if name in old:
        return {key: value for key, value in old[name].items() if key != 'frames'}
    new = poses.get(name, {}).get('new', {})
    return dict(loop=False, fps=new.get('fps', 12), phase_breaks=new.get('phase_breaks', [count // 3, count * 2 // 3]),
                segment_sync=new.get('segment_sync', False), anchor_mode=new.get('anchor_mode', 'feet'), timeline=[])


def write_atlas(path, header, clips, entries):
    atlas = dict(header)
    atlas['clips'] = {}
    for name, (meta, count) in clips.items():
        entry = dict(meta)
        entry['frames'] = [entries[(name, index)] for index in range(count)]
        atlas['clips'][name] = entry
    path.write_text(json.dumps(atlas, ensure_ascii=False, indent=2), encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', default='tanjiro')
    args = parser.parse_args()
    character = args.character
    folder = ROOT / 'art/characters' / character
    revision = spec(character)['revision']
    poses = read(POSES / (character + '.json'))['clips']
    old_base = previous(character, 'atlas.json')
    old_round = previous(character, 'round-atlas.json')
    old_awake = previous(character, 'awakening/atlas.json')
    header = dict(canvas_size=[1024, 640], feet_anchor=[448, 568], source_height=340, canonical_height=70, revision=revision)
    # Helper clips (key drawings another clip is assembled from) never ship.
    names = ['idle'] + [name for name in poses if not poses[name].get('helper')]
    available = {name: frames_of(character, name) for name in names}
    missing = [name for name, frames in available.items() if not frames]
    if missing:
        raise SystemExit('Missing processed clips: ' + ', '.join(missing))
    flipped = [name for name in names if poses.get(name, {}).get('mirror')]
    drawn = available
    available = {name: [mirrored(image) for image in frames] if name in flipped else frames for name, frames in drawn.items()}
    base_names = [n for n in names if n not in ROUND and n != 'awakening_start']
    base_meta = {n: (clip_metadata(n, len(available[n]), old_base['clips'], poses), len(available[n])) for n in base_names}
    round_meta = {n: (clip_metadata(n, len(available[n]), old_round['clips'], poses), len(available[n])) for n in ROUND}
    awake_names = base_names + list(ROUND) + ['awakening_start']
    awake_meta = {n: (clip_metadata(n, len(available[n]), {**old_base['clips'], **old_round['clips'], **old_awake['clips']}, poses), len(available[n]))
                  for n in awake_names}
    for name, (meta, count) in base_meta.items():
        old = old_base['clips'].get(name)
        if old and name != 'idle' and len(old['frames']) != count:
            raise SystemExit('%s: %d frames, the previous atlas had %d' % (name, count, len(old['frames'])))
    entries, pages = pack({(n, i): img for n in base_names for i, img in enumerate(available[n])}, folder, 'atlas')
    write_atlas(folder / 'atlas.json', header, base_meta, entries)
    round_entries, round_pages = pack({(n, i): img for n in ROUND for i, img in enumerate(available[n])}, folder, 'round')
    write_atlas(folder / 'round-atlas.json', header, round_meta, round_entries)
    marks = {}
    baked = {}
    for name in awake_names:
        # The mark is found on the drawing as generated (facing right), then flipped with it.
        for index, image in enumerate(drawn[name]):
            array, count = awaken.bake(np.asarray(image))
            baked[(name, index)] = mirrored(Image.fromarray(array, 'RGBA')) if name in flipped else Image.fromarray(array, 'RGBA')
            marks.setdefault(name, []).append(count)
    awake_entries, awake_pages = pack(baked, folder / 'awakening', 'atlas')
    write_atlas(folder / 'awakening/atlas.json', header, awake_meta, awake_entries)
    record = dict(revision=revision, clips={n: c for n, (_, c) in base_meta.items()}, round_clips={n: c for n, (_, c) in round_meta.items()},
                  awakened_clips={n: c for n, (_, c) in awake_meta.items()}, pages=dict(base=pages, round=round_pages, awakening=awake_pages),
                  awakening_marks=marks, mirrored_clips=flipped,
                  outputs={rel(path): sha256(path) for path in [folder / 'atlas.json', folder / 'round-atlas.json'] + sorted(folder.glob('atlas-*.png')) + sorted(folder.glob('round-*.png'))
                           + [folder / 'awakening/atlas.json'] + sorted((folder / 'awakening').glob('atlas-*.png'))})
    save(production(character) / 'pack.json', record)
    print('packed %s: %d base clips (%d pages), %d round clips, %d awakened clips (%d pages)' % (
        character, len(base_meta), pages, len(round_meta), len(awake_meta), awake_pages))


if __name__ == '__main__':
    main()
