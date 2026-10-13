"""Turn v3 generated sheets into registered 1024x640 canvas frames plus QA records.

Per generated sheet (one "part" of a clip):
  1. key the background (process_anime_art.cutout keeps native alpha or keys magenta);
  2. lock material colours to the approved idle (palette.lock, once per sheet);
  3. separate the drawings (process_anime_art.sprite_components);
  4. measure each drawing's head ruler (anatomy.head) and use the sheet median for
     ONE scale per sheet, so the head always has the approved runtime size;
  5. register the body root (uniform centroid) to the feet anchor x and the sole to the floor.
Writes output/imagegen/<id>-v3/imports/<clip>.json and review sheets in artifacts/art-v3/<id>/.

Usage: python tools/art_v3/process.py --clips walk,stand_light,water_slash [--character tanjiro]
"""
import argparse
import json
import statistics

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from common import ROOT, production, read, rel, save, sha256
import anatomy
import palette
import process_anime_art as legacy

CANVAS = (1024, 640)
ANCHOR = (448, 568)
APPROVED_HEAD_PX = 158          # approved idle candidate, hair top to chin
RUNTIME_HEAD_PX = 340 * 166 / 925  # model sheet ratio at the 340 px runtime standing height
RULER_TOLERANCE = 0.08


def canonical(character):
    out = production(character)
    key = np.asarray(Image.open(out / 'references/approved-idle-candidate.png').convert('RGBA'))
    measured = anatomy.head(key)
    scale = RUNTIME_HEAD_PX / APPROVED_HEAD_PX
    return dict(ruler=measured['ruler'], runtime_ruler=measured['ruler'] * scale, scale=scale,
                palette=palette.stats(key), key=key)


PELVIS_HEIGHT = round(340 * 34 / 70)  # pelvis above the feet anchor for rotating poses (old pipeline convention)


def place(drawing, scale, mode='feet'):
    """Scale one drawing onto the shared canvas.
    feet:   body root x to the anchor, lowest pixel (soles) on the floor;
    lying:  same as feet (the lowest pixel is the back or side on the floor);
    pelvis: body centre at PELVIS_HEIGHT above the anchor, for flips and airborne rotations."""
    array = np.asarray(drawing)
    root = anatomy.root_x(array)
    scaled = drawing.resize((max(1, round(drawing.width * scale)), max(1, round(drawing.height * scale))), Image.Resampling.LANCZOS)
    if mode == 'pelvis':
        centre_y = anatomy.root_y(array)
        at = (round(ANCHOR[0] - root * scale), round(ANCHOR[1] - PELVIS_HEIGHT - centre_y * scale))
    else:
        at = (round(ANCHOR[0] - root * scale), round(ANCHOR[1] - anatomy.sole_y(array) * scale))
    if mode == 'pelvis' and at[1] + scaled.height > CANVAS[1]:
        # An upside-down flip can reach below the canvas; lift it just enough.
        at = (at[0], CANVAS[1] - scaled.height)
    canvas = Image.new('RGBA', CANVAS)
    clipped = at[0] < 0 or at[1] < 0 or at[0] + scaled.width > CANVAS[0] or at[1] + scaled.height > CANVAS[1]
    canvas.alpha_composite(scaled, (max(0, at[0]), max(0, at[1])), (max(0, -at[0]), max(0, -at[1])))
    return canvas, dict(root_x=round(root, 1), anchor_mode=mode, offset=list(at), clipped=clipped)


def separate(sheet, count):
    """Drawings left to right. When figures touch (a blade reaching the next
    drawing), thin links are eroded away to find each body, and a watershed gives
    every pixel to the nearest body."""
    try:
        return legacy.sprite_components(sheet, count, count)
    except ValueError:
        pass
    rgba = np.asarray(sheet)
    solid = (rgba[:, :, 3] > 110).astype(np.uint8)
    cell = sheet.width / count
    order = None
    for size in (9, 15, 21, 29):
        core = cv2.erode(solid, np.ones((size, size), np.uint8))
        n, labels, stats, centres = cv2.connectedComponentsWithStats(core, 8)
        # One body per column: the largest core whose centre lies in that column.
        picks = []
        for column in range(count):
            inside = [label for label in range(1, n) if column * cell <= centres[label][0] < (column + 1) * cell]
            if inside:
                picks.append(max(inside, key=lambda label: stats[label, cv2.CC_STAT_AREA]))
        if len(picks) == count and len(set(picks)) == count:
            order = picks
            break
    if order is None:
        return split_columns(sheet, count)
    markers = np.zeros(solid.shape, np.int32)
    for index, label in enumerate(order):
        markers[labels == label] = index + 1
    markers[cv2.dilate(solid, np.ones((3, 3), np.uint8)) == 0] = count + 1
    shed = cv2.watershed(cv2.cvtColor(rgba[:, :, 3], cv2.COLOR_GRAY2BGR), markers)
    result = []
    for index in range(count):
        owned = cv2.dilate((shed == index + 1).astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
        piece = rgba.copy()
        piece[~owned, 3] = 0
        image = Image.fromarray(piece, 'RGBA')
        bounds = image.getbbox()
        if bounds is None:
            return split_columns(sheet, count)
        result.append((bounds, image.crop(bounds)))
    areas = [int((np.asarray(image)[:, :, 3] > 160).sum()) for _, image in result]
    if min(areas) < max(areas) * 0.25:
        return split_columns(sheet, count)
    return result


def split_columns(sheet, count):
    """Last resort: cut at the column borders, keep each column's main figure and
    any small detached details, drop pieces of the neighbour that touch the border."""
    result = []
    cell = sheet.width / count
    for index in range(count):
        box = (round(index * cell), 0, round((index + 1) * cell), sheet.height)
        piece = np.asarray(sheet.crop(box)).copy()
        solid = (piece[:, :, 3] > 110).astype(np.uint8)
        n, labels, stats, _ = cv2.connectedComponentsWithStats(solid, 8)
        if n > 1:
            main = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
            keep = np.zeros(solid.shape, bool)
            for label in range(1, n):
                x, y, w, h, area = stats[label]
                if label == main or not (x <= 2 or x + w >= solid.shape[1] - 2):
                    keep |= labels == label
            piece[~cv2.dilate(keep.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool), 3] = 0
        column = Image.new('RGBA', sheet.size)
        column.paste(Image.fromarray(piece, 'RGBA'), box[:2])
        bounds = column.getbbox()
        result.append((bounds, column.crop(bounds)))
    return result


def body_height(rgba):
    """Hair top to sole, independent of where the blade points."""
    measured = anatomy.head(rgba)
    top = measured['box'][1] if measured else int(np.nonzero(rgba[:, :, 3] > 150)[0].min())
    return anatomy.sole_y(rgba) - top


def process_clip(character, clip, jobs, canon, upright=False, pose=None):
    """Overlap frames (padding repeated from the previous sheet) calibrate a sheet's
    scale directly against already registered drawings; other sheets use the head ruler."""
    reference = np.asarray(Image.open(production(character) / 'imports/idle/frame-00.png').convert('RGBA'))
    idle_height = body_height(reference)
    frames = {}
    records = []
    parts = []
    sheets = []
    for job in sorted(jobs, key=lambda j: j['metadata']['part']):
        raw = ROOT / job['out']
        sheet = np.asarray(legacy.cutout(Image.open(raw)))
        before = palette.stats(sheet)
        locked, shifts = palette.lock(sheet, canon['palette'], before)
        after = palette.stats(locked)
        meta = job['metadata']
        drawings = separate(Image.fromarray(locked, 'RGBA'), meta['count'])
        heads = [anatomy.head(np.asarray(image)) for _, image in drawings]
        rulers = [h['ruler'] for h in heads if h]
        # Raised arms or a turned head only ever hide part of the head, so with two
        # drawings the clearer (larger) head is the reference; three or more use the median.
        if not rulers:
            part_ruler = canon['ruler']
        elif len(rulers) <= 2:
            part_ruler = max(rulers)
        else:
            part_ruler = statistics.median(rulers)
        sheets.append(dict(job=job, raw=raw, meta=meta, drawings=drawings, heads=heads, part_ruler=part_ruler,
                           head_scale=canon['runtime_ruler'] / part_ruler, shifts=shifts, before=before, after=after, measured=bool(rulers)))
    # Upright drawings measure their heads reliably. In flips and falls the head is
    # often hidden or upside down, so a rotated sheet far from the clip median takes
    # the median instead (preferring the upright sheets' median).
    pose = pose or {}
    def rotated(data):
        drawn = [i for i in data['meta']['frame_indices'] if i not in (data['meta'].get('overlap') or [])]
        return any((pose.get('ground_mode', 'feet') if i in pose.get('ground_frames', []) else pose.get('anchor', 'feet')) != 'feet' for i in drawn)
    upright_scales = [d['head_scale'] for d in sheets if d['measured'] and not rotated(d)]
    clip_median = statistics.median(upright_scales or [d['head_scale'] for d in sheets if d['measured']] or [canon['scale']])
    for data in sheets:
        job, raw, meta, drawings, heads, part_ruler = data['job'], data['raw'], data['meta'], data['drawings'], data['heads'], data['part_ruler']
        scale = data['head_scale']
        method = 'head-ruler'
        if not data['measured'] or (rotated(data) and abs(scale / clip_median - 1) > 0.12):
            scale = clip_median
            method = 'clip-median'
        overlap = meta.get('overlap') or []
        calibrations = []
        for (bbox, image), index in zip(drawings, meta['frame_indices']):
            if index in overlap and index in frames:
                calibrations.append(body_height(np.asarray(frames[index])) / body_height(np.asarray(image)))
        if calibrations:
            scale = statistics.median(calibrations)
            method = 'overlap'
        before, after, shifts = data['before'], data['after'], data['shifts']
        parts.append(dict(id=job['id'], source=job['out'], sha256=sha256(raw), ruler=round(part_ruler, 2), scale=round(scale, 4), scale_method=method,
                          resample_vs_idle=round(scale / canon['scale'], 3), palette_shift=shifts,
                          palette_delta_e_before={k: round(palette.delta_e(v, canon['palette'][k]), 2) for k, v in before.items() if k in canon['palette']},
                          palette_delta_e_after={k: round(palette.delta_e(v, canon['palette'][k]), 2) for k, v in after.items() if k in canon['palette']}))
        for (bbox, image), head, index in zip(drawings, heads, meta['frame_indices']):
            if index in overlap:
                continue
            mode = pose.get('anchor', 'feet')
            if index in pose.get('ground_frames', []):
                mode = pose.get('ground_mode', 'feet')
            canvas, placement = place(image, scale, mode)
            ratio = head['ruler'] / part_ruler if head else None
            flags = []
            notes = []
            if ratio is not None and ratio > 1 + RULER_TOLERANCE:
                flags.append('head %.0f%% larger than the sheet reference' % ((ratio - 1) * 100))
            elif ratio is not None and ratio < 0.85:
                notes.append('head partly hidden or turned (%.0f%%)' % (ratio * 100))
            if head is None:
                notes.append('head not measured (back view, flip or occlusion)')
            if placement['clipped']:
                flags.append('clipped on canvas')
            height_ratio = body_height(np.asarray(canvas)) / idle_height
            # Standing fully upright is about 5% taller than the bent-knee guard.
            if upright and mode == 'feet' and not 0.95 <= height_ratio <= 1.07:
                flags.append('height %.0f%% of the idle' % (height_ratio * 100))
            placement['height_vs_idle'] = round(height_ratio, 3)
            frames[index] = canvas
            records.append(dict(frame=index, part=job['id'], crop=list(bbox), head_ruler=round(head['ruler'], 2) if head else None,
                                head_box=head['box'] if head else None, ratio_to_sheet=round(ratio, 3) if ratio else None,
                                scale=round(scale, 4), flags=flags, notes=notes, **placement))
    ordered = [frames[i] for i in sorted(frames)]
    save_frames(character, clip, ordered)
    record = dict(character=character, clip=clip, canvas_size=list(CANVAS), feet_anchor=list(ANCHOR),
                  runtime_head_ruler=round(canon['runtime_ruler'], 2), parts=parts, frames=sorted(records, key=lambda r: r['frame']))
    save(production(character) / 'imports' / (clip + '.json'), record)
    return ordered, record


def save_frames(character, clip, frames):
    folder = production(character) / 'imports' / clip
    folder.mkdir(parents=True, exist_ok=True)
    for stale in folder.glob('frame-*.png'):
        stale.unlink()
    for index, frame in enumerate(frames):
        frame.save(folder / ('frame-%02d.png' % index))


def process_idle(character, canon):
    """The approved idle loop: warped from the key, so it shares the key's scale exactly."""
    folder = production(character) / 'imports/idle-warp'
    drawings = [Image.open(path).convert('RGBA') for path in sorted(folder.glob('idle-*.png'))]
    root = anatomy.root_x(canon['key'])
    sole = anatomy.sole_y(canon['key'])
    frames, records = [], []
    for index, drawing in enumerate(drawings):
        scaled = drawing.resize((round(drawing.width * canon['scale']), round(drawing.height * canon['scale'])), Image.Resampling.LANCZOS)
        at = (round(ANCHOR[0] - root * canon['scale']), round(ANCHOR[1] - sole * canon['scale']))
        canvas = Image.new('RGBA', CANVAS)
        canvas.alpha_composite(scaled, at)
        frames.append(canvas)
        records.append(dict(frame=index, source=rel(folder / ('idle-%02d.png' % index)), scale=round(canon['scale'], 4), offset=list(at), flags=[]))
    save_frames(character, 'idle', frames)
    record = dict(character=character, clip='idle', canvas_size=list(CANVAS), feet_anchor=list(ANCHOR), cycle=True,
                  source='output/imagegen/%s-v3/references/approved-idle-candidate.png' % character, frames=records)
    save(production(character) / 'imports' / 'idle.json', record)
    return frames, record


def review(character, clip, frames, record, fps, reference=None):
    """Contact grid (approved idle first, floor line, head ratio per drawing) and a timed GIF."""
    folder = ROOT / 'artifacts/art-v3' / character
    folder.mkdir(parents=True, exist_ok=True)
    try:
        font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 20)
    except OSError:
        font = ImageFont.load_default()
    shown = ([reference] if reference is not None else []) + list(frames)
    box = None
    for frame in shown:
        b = frame.getbbox()
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    box = (box[0] - 10, box[1] - 10, box[2] + 10, box[3] + 4)
    width, height = box[2] - box[0], box[3] - box[1]
    zoom, columns = 1.4, 5
    cell = (int(width * zoom), int(height * zoom) + 30)
    rows = (len(shown) + columns - 1) // columns
    sheet = Image.new('RGB', (cell[0] * columns, cell[1] * rows), '#1b2233')
    draw = ImageDraw.Draw(sheet)
    for index, frame in enumerate(shown):
        x, y = (index % columns) * cell[0], (index // columns) * cell[1]
        piece = frame.crop(box).resize((cell[0], cell[1] - 30), Image.Resampling.LANCZOS)
        sheet.paste(piece, (x, y + 30), piece)
        floor = y + 30 + int((ANCHOR[1] - box[1]) * zoom)
        draw.line((x, floor, x + cell[0], floor), fill='#4a5a7a')
        if reference is not None and index == 0:
            label, colour = 'idle (approved reference)', '#9fd3ff'
        else:
            info = record['frames'][index - (1 if reference is not None else 0)]
            label = '%s %d  head %.2f' % (clip, info.get('frame', index), info.get('ratio_to_sheet') or 0)
            colour = '#ff7070' if info.get('flags') else '#ffd27f'
        draw.text((x + 6, y + 4), label, fill=colour, font=font)
    _save_unlocked(sheet, folder / ('%s-sheet.png' % clip))
    animation = []
    for frame in frames:
        canvas = Image.new('RGB', (width, height), '#1b2233')
        piece = frame.crop(box)
        canvas.paste(piece, (0, 0), piece)
        animation.append(canvas)
    _save_unlocked(animation[0], folder / ('%s.gif' % clip), save_all=True, append_images=animation[1:], duration=int(1000 / fps), loop=0)


def _save_unlocked(image, path, **options):
    """A review file open in a Windows viewer is locked; fall back to a numbered name."""
    for attempt in range(10):
        target = path if attempt == 0 else path.with_name('%s-%d%s' % (path.stem, attempt, path.suffix))
        try:
            image.save(target, **options)
            return target
        except OSError:
            continue
    raise OSError('cannot write review file ' + str(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', default='tanjiro')
    parser.add_argument('--clips', required=True)
    args = parser.parse_args()
    canon = canonical(args.character)
    poses = read(ROOT / 'tools/art_v3/poses' / (args.character + '.json'))['clips']
    jobs = read(production(args.character) / 'jobs.json', [])
    atlas = json.loads((ROOT / 'art/characters' / args.character / 'atlas.json').read_text(encoding='utf-8'))
    for clip in args.clips.split(','):
        if clip == 'idle':
            frames, record = process_idle(args.character, canon)
            review(args.character, clip, frames, dict(frames=[dict(ratio_to_sheet=1.0, flags=[]) for _ in frames]), 10)
            print('idle: %d frames from the approved key' % len(frames))
            continue
        clip_jobs = [j for j in jobs if j.get('metadata', {}).get('clip') == clip and j['id'].startswith(args.character + '-v3-' + clip + '-p')
                     and not j.get('superseded_by')]
        if not clip_jobs or not all((ROOT / j['out']).exists() for j in clip_jobs):
            print('skip', clip, '(sheets missing)')
            continue
        frames, record = process_clip(args.character, clip, clip_jobs, canon, bool(poses.get(clip, {}).get('upright')), poses.get(clip))
        reference = Image.open(production(args.character) / 'imports/idle/frame-00.png').convert('RGBA')
        fps = atlas['clips'].get(clip, {}).get('fps') or poses.get(clip, {}).get('new', {}).get('fps', 12)
        review(args.character, clip, frames, record, fps, reference)
        flagged = [r for r in record['frames'] if r['flags']]
        print('%s: %d frames, sheet scales %s, flagged %d' % (clip, len(frames), [p['resample_vs_idle'] for p in record['parts']], len(flagged)))
        for r in flagged:
            print('   frame', r['frame'], r['flags'])


if __name__ == '__main__':
    main()
