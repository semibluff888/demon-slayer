"""Pack processed v3 frames into the shipped atlases.

Writes art/characters/<id>/atlas.json + atlas-N.png (combat clips), round-atlas.json +
round-N.png (round intro/victory/defeat) and awakening/atlas.json + atlas-N.png (every
clip derived by awaken.py, identical geometry: Tanjiro's forehead mark, Zenitsu's Godspeed grade). Existing clips
keep their timing metadata (fps, loop, phase_breaks, segment_sync, timeline, anchor
mode) from the previous atlases; new clips take theirs from the pose script; idle
becomes the authored 12-frame loop ("cycle": true). Stale pages are removed.
Clips marked "mirror" in the pose script are drawn facing right like every sheet but
ship flipped around the feet anchor: a throw victim is drawn with its thrower's
facing, so its art faces left (toward the thrower), as in every other atlas.
A spec "awakening" mode "keep" (Nezuko: her demon form is not redrawn) leaves the
committed awakened atlas and its pages as they are; a clip it lacks (a new move's)
borrows the frames and timing of the old clip named in the spec's "fallback". Clips
marked "keep_shipped" in the pose script (Nezuko's MAX, only ever shown in that kept
form) ship their committed drawings in the normal atlas instead of processed frames.

Usage: python tools/art_v3/pack.py [--character tanjiro]
"""
import argparse
import copy
import io
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

from common import ROOT, POSES, production, read, rel, save, sha256, spec
import anatomy
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


def shipped_frames(character, clip):
    """A clip's canvas frames cut from the committed atlas and its committed pages."""
    atlas = previous(character, 'atlas.json')
    pages = {}
    frames = []
    for entry in atlas['clips'][clip]['frames']:
        if entry['texture'] not in pages:
            data = subprocess.run(['git', 'show', 'HEAD:art/characters/%s/%s' % (character, entry['texture'])], cwd=ROOT,
                                  capture_output=True, check=True).stdout
            pages[entry['texture']] = Image.open(io.BytesIO(data)).convert('RGBA')
        x, y, width, height = entry['region']
        image = Image.new('RGBA', tuple(atlas['canvas_size']))
        image.paste(pages[entry['texture']].crop((x, y, x + width, y + height)), tuple(entry['offset']))
        frames.append(image)
    return frames


def kept_awakening(old_awake, names, fallback):
    """The committed awakened atlas, plus the clips it lacks as copies of their fallbacks.
    A fallback is a clip name, or {"clip": name, "frames": [indices]} for a part of one
    (a landing taken from the jump's landing drawings); other keys override its timing."""
    atlas = copy.deepcopy(old_awake)
    added = {}
    for name in names:
        if name in atlas['clips']:
            continue
        source = fallback.get(name)
        settings = dict(source) if isinstance(source, dict) else {'clip': source}
        if settings['clip'] not in old_awake['clips']:
            raise SystemExit('kept awakened atlas has no %s and no fallback clip for it' % name)
        entry = copy.deepcopy(old_awake['clips'][settings.pop('clip')])
        picked = settings.pop('frames', None)
        if picked is not None:
            entry['frames'] = [entry['frames'][index] for index in picked]
        entry.update(settings)
        atlas['clips'][name] = entry
        added[name] = source
    return atlas, added


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
        meta = {key: value for key, value in old[name].items() if key != 'frames'}
        # A redrawn clip whose drawings now split the move differently (Zenitsu's 2D:
        # the wind-up moved into the startup, one held sweep frame) sets its own breaks.
        if 'phase_breaks' in poses.get(name, {}):
            meta['phase_breaks'] = poses[name]['phase_breaks']
        return meta
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
    anatomy.configure(character)
    folder = ROOT / 'art/characters' / character
    revision = spec(character)['revision']
    poses = read(POSES / (character + '.json'))['clips']
    old_base = previous(character, 'atlas.json')
    old_round = previous(character, 'round-atlas.json')
    old_awake = previous(character, 'awakening/atlas.json')
    header = dict(canvas_size=[1024, 640], feet_anchor=[448, 568], source_height=340, canonical_height=70, revision=revision)
    stance = spec(character).get('qa', {}).get('idle_vs_upright')
    if stance:
        # A low idle (Zenitsu's iai stance): its share of the standing height, so size
        # comparisons between characters measure standing bodies (fate_revision_tests).
        header['idle_vs_upright'] = stance
    # Helper clips (key drawings another clip is assembled from) never ship.
    names = ['idle'] + [name for name in poses if not poses[name].get('helper')]
    kept_clips = [name for name in names if poses.get(name, {}).get('keep_shipped')]
    available = {name: shipped_frames(character, name) if name in kept_clips else frames_of(character, name) for name in names}
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
    for name, (meta, count) in base_meta.items():
        old = old_base['clips'].get(name)
        if old and name != 'idle' and len(old['frames']) != count:
            raise SystemExit('%s: %d frames, the previous atlas had %d' % (name, count, len(old['frames'])))
    entries, pages = pack({(n, i): img for n in base_names for i, img in enumerate(available[n])}, folder, 'atlas')
    write_atlas(folder / 'atlas.json', header, base_meta, entries)
    round_entries, round_pages = pack({(n, i): img for n in ROUND for i, img in enumerate(available[n])}, folder, 'round')
    write_atlas(folder / 'round-atlas.json', header, round_meta, round_entries)
    marks = {}
    fallbacks = {}
    settings = awaken.settings()
    if settings.get('mode') == 'keep':
        kept, fallbacks = kept_awakening(old_awake, awake_names, settings.get('fallback', {}))
        (folder / 'awakening/atlas.json').write_text(json.dumps(kept, ensure_ascii=False, indent=2), encoding='utf-8')
        awake_counts = {n: len(clip['frames']) for n, clip in kept['clips'].items()}
        awake_pages = len(list((folder / 'awakening').glob('atlas-*.png')))
    else:
        # The awakened atlas shares every clip's timing with the normal atlases (a clip that
        # moved to the round atlas, such as Akaza's 18-frame round intro, must not keep the
        # previous awakened atlas's 12-frame timing); only awakening_start is its own.
        shared = {**base_meta, **round_meta}
        awake_meta = {n: shared[n] if n in shared else
                      (clip_metadata(n, len(available[n]), {**old_base['clips'], **old_round['clips'], **old_awake['clips']}, poses), len(available[n]))
                      for n in awake_names}
        baked = {}
        for name in awake_names:
            # The mark or grade is found on the drawing as generated (facing right), then flipped with it.
            for index, image in enumerate(drawn[name]):
                array, count = awaken.bake(np.asarray(image))
                baked[(name, index)] = mirrored(Image.fromarray(array, 'RGBA')) if name in flipped else Image.fromarray(array, 'RGBA')
                marks.setdefault(name, []).append(count)
        awake_entries, awake_pages = pack(baked, folder / 'awakening', 'atlas')
        write_atlas(folder / 'awakening/atlas.json', header, awake_meta, awake_entries)
        awake_counts = {n: c for n, (_, c) in awake_meta.items()}
    record = dict(revision=revision, clips={n: c for n, (_, c) in base_meta.items()}, round_clips={n: c for n, (_, c) in round_meta.items()},
                  awakened_clips=awake_counts, pages=dict(base=pages, round=round_pages, awakening=awake_pages),
                  awakening_marks=marks, mirrored_clips=flipped,
                  outputs={rel(path): sha256(path) for path in [folder / 'atlas.json', folder / 'round-atlas.json'] + sorted(folder.glob('atlas-*.png')) + sorted(folder.glob('round-*.png'))
                           + [folder / 'awakening/atlas.json'] + sorted((folder / 'awakening').glob('atlas-*.png'))})
    if settings.get('mode') == 'keep':
        record.update(awakening_kept=old_awake.get('revision'), awakening_fallbacks=fallbacks, shipped_clips=kept_clips)
    save(production(character) / 'pack.json', record)
    print('packed %s: %d base clips (%d pages), %d round clips, %d awakened clips (%d pages)' % (
        character, len(base_meta), pages, len(round_meta), len(awake_counts), awake_pages))


if __name__ == '__main__':
    main()
