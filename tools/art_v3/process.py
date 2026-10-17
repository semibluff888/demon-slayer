"""Turn v3 generated sheets into registered 1024x640 canvas frames plus QA records.

Per generated sheet (one "part" of a clip):
  1. key the background (common.cutout: native alpha, else the spec's magenta or green key);
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
from PIL import Image, ImageDraw, ImageFont, ImageOps

from common import ROOT, cutout, production, read, rel, save, sha256, spec
import anatomy
import idle_warp
import palette
import process_anime_art as legacy

CANVAS = (1024, 640)
ANCHOR = (448, 568)
RULER_TOLERANCE = 0.08
LENGTH_LIMIT = 1.05             # longest stretched-out body vs the approved idle (upright is ~5% taller)


def canonical(character):
    """The approved key and its scale. spec/<id>.json "ruler": the key's hair top to chin
    (approved_head_px) and the model sheet's head and height give the runtime head at the
    runtime standing height. Optional "production_head_scale": the model draws some
    characters' production sheets with a larger head than their key (Akaza: about 7%), so
    generated sheets aim at a head this much larger and their bodies match the idle; the
    idle and other warped clips keep the key's own scale. Also selects the character's
    colour classes (anatomy.configure)."""
    data = anatomy.configure(character)
    ruler = data['ruler']
    out = production(character)
    key = np.asarray(Image.open(out / 'references/approved-idle-candidate.png').convert('RGBA'))
    measured = anatomy.head(key)
    runtime_head = ruler['runtime_standing_px'] * ruler['model_head_px'] / ruler['model_height_px']
    scale = runtime_head / ruler['approved_head_px']
    # A wide crouching key's main axis is shorter than the body; the spec then gives it.
    length = data.get('qa', {}).get('length_px') or anatomy.body_axes(key)[0]
    return dict(ruler=measured['ruler'], runtime_ruler=measured['ruler'] * scale * ruler.get('production_head_scale', 1.0), scale=scale,
                length=length, palette=palette.stats(key), key=key, qa=data.get('qa', {}),
                warp_pad=tuple(data.get('warp_pad', WARP_PAD)))


PELVIS_HEIGHT = round(340 * 34 / 70)  # pelvis above the feet anchor for rotating poses (old pipeline convention)


def place(drawing, scale, mode='feet', centred=False):
    """Scale one drawing onto the shared canvas.
    feet:   body root x to the anchor, lowest pixel (soles) on the floor;
    lying:  body root x to the anchor, lowest row of the body itself on the floor (a dropped
            katana or an outstretched hand reaching lower would otherwise lift the body);
    pelvis: body centre at PELVIS_HEIGHT above the anchor, for flips and airborne rotations.
    centred (a lying pose's "lying_centred"): the middle of the body itself, not the uniform
    centroid, goes to the anchor x (Akaza's long torso put his head past a corner)."""
    array = np.asarray(drawing)
    root = anatomy.root_x(array)
    if centred:
        columns = np.nonzero(anatomy.solid_body(array).any(axis=0))[0]
        root = (columns.min() + columns.max() + 1) / 2.0
    scaled = drawing.resize((max(1, round(drawing.width * scale)), max(1, round(drawing.height * scale))), Image.Resampling.LANCZOS)
    if mode == 'pelvis':
        centre_y = anatomy.root_y(array)
        at = (round(ANCHOR[0] - root * scale), round(ANCHOR[1] - PELVIS_HEIGHT - centre_y * scale))
    else:
        bottom = anatomy.body_bottom(array) if mode == 'lying' else anatomy.sole_y(array)
        at = (round(ANCHOR[0] - root * scale), round(ANCHOR[1] - bottom * scale))
    if mode == 'pelvis' and at[1] + scaled.height > CANVAS[1]:
        # An upside-down flip can reach below the canvas; lift it just enough.
        at = (at[0], CANVAS[1] - scaled.height)
    canvas = Image.new('RGBA', CANVAS)
    clipped = at[0] < 0 or at[1] < 0 or at[0] + scaled.width > CANVAS[0] or at[1] + scaled.height > CANVAS[1]
    canvas.alpha_composite(scaled, (max(0, at[0]), max(0, at[1])), (max(0, -at[0]), max(0, -at[1])))
    return canvas, dict(root_x=round(root, 1), anchor_mode=mode, offset=list(at), clipped=clipped)


def _ink(rgba):
    """Luminance weighted by coverage: line art on an empty background."""
    rgb = rgba[:, :, :3].astype(np.float32)
    return (rgb @ np.array([0.299, 0.587, 0.114], np.float32)) * (rgba[:, :, 3:4].astype(np.float32)[:, :, 0] / 255.0)


def register(drawing, target, guess, band=(0.55, 1.0)):
    """Lays a drawing onto a registered canvas frame of the same body by the lower
    body only (legs, feet, scabbard), which the edited arms and blade never cover.
    `band` is the matched share of the target's height from the hair top (an edit that
    moves a leg registers by the upper body instead, e.g. (0.0, 0.55)).
    Searches scale around `guess` and a small offset; returns (canvas, placement)."""
    goal = np.asarray(target)
    rows = np.nonzero(goal[:, :, 3] > 150)[0]
    top, sole = int(rows.min()), int(rows.max()) + 1
    band = slice(top + int((sole - top) * band[0]), top + int((sole - top) * band[1]))
    cols = np.nonzero((goal[band, :, 3] > 150).any(axis=0))[0]
    x0, x1 = int(cols.min()) - 4, int(cols.max()) + 5
    template = _ink(goal[band, x0:x1])
    best = None
    for factor in np.linspace(0.8, 1.2, 81):
        scale = guess * factor
        canvas, placement = place(drawing, scale, 'feet')
        ink = _ink(np.asarray(canvas))
        y0, margin = band.start, 24
        window = ink[max(0, y0 - margin):band.stop + margin, max(0, x0 - margin):x1 + margin]
        result = cv2.matchTemplate(window, template, cv2.TM_CCOEFF_NORMED)
        _, score, _, at = cv2.minMaxLoc(result)
        dx = at[0] + max(0, x0 - margin) - x0
        dy = at[1] + max(0, y0 - margin) - y0
        if best is None or score > best[0]:
            best = (score, scale, -dx, -dy)
    score, scale, dx, dy = best
    canvas, placement = place(drawing, scale, 'feet')
    shifted = Image.new('RGBA', canvas.size)
    shifted.alpha_composite(canvas, (max(0, dx), max(0, dy)), (max(0, -dx), max(0, -dy)))
    placement.update(offset=[placement['offset'][0] + dx, placement['offset'][1] + dy], anchor_mode='registered',
                     registration=dict(scale=round(scale, 4), score=round(float(score), 3), exact=float(scale)))
    return shifted, placement


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


def unshown(pose):
    """Frames whose own drawing is never shown: replaced by copy_frames and not copied
    anywhere else in the clip (a frame swapped with another still shows, elsewhere)."""
    copies = pose.get('copy_frames', {})
    sources = {source for source in copies.values() if not isinstance(source, str)}
    return {int(target) for target in copies} - sources


def body_height(rgba):
    """Hair top to sole, independent of where the blade points."""
    measured = anatomy.head(rgba)
    top = measured['box'][1] if measured else int(np.nonzero(rgba[:, :, 3] > 150)[0].min())
    return anatomy.sole_y(rgba) - top


def process_clip(character, clip, jobs, canon, band=None, pose=None):
    """Overlap frames (padding repeated from the previous sheet) calibrate a sheet's
    scale directly against already registered drawings; other sheets use the head ruler.
    `band` is the allowed height of standing drawings relative to the idle (spec "qa")."""
    reference = np.asarray(Image.open(production(character) / 'imports/idle/frame-00.png').convert('RGBA'))
    idle_height = body_height(reference)
    pose = pose or {}

    def mode_of(index):
        return pose.get('ground_mode', 'feet') if index in pose.get('ground_frames', []) else pose.get('anchor', 'feet')

    frames = {}
    records = []
    parts = []
    sheets = []
    for job in sorted(jobs, key=lambda j: j['metadata']['part']):
        raw = ROOT / job['out']
        sheet = np.asarray(cutout(Image.open(raw), spec(character)))
        before = palette.stats(sheet)
        locked, shifts = palette.lock(sheet, canon['palette'], before)
        after = palette.stats(locked)
        meta = job['metadata']
        drawings = separate(Image.fromarray(locked, 'RGBA'), meta['count'])
        mirrored = pose.get('mirror_frames', [])
        if mirrored:
            # Drawn facing right and turned round here: Akaza's back throw faces LEFT,
            # head and all, while he slams (the model draws a turned-away body with the
            # face still to the right).
            drawings = [(bounds, ImageOps.mirror(image) if index in mirrored else image)
                        for (bounds, image), index in zip(drawings, meta['frame_indices'])]
        heads = [anatomy.head(np.asarray(image)) for _, image in drawings]
        overlap = meta.get('overlap') or []
        # "Hair top to sole" of a lying body depends on how its legs happen to be drawn,
        # so a lying overlap cannot calibrate the sheet (it shrank the knockdown's final
        # drawing to 66%); the sheet then measures its own drawings' heads.
        if overlap and all(mode_of(i) == 'lying' for i in overlap):
            rulers = [h['ruler'] for h, i in zip(heads, meta['frame_indices']) if h and i not in overlap]
        else:
            # Drawings that copy_frames / settle replace later are never shown, so they do
            # not measure the sheet (2D's last sheet took its scale from a crouch drawn with
            # a bigger head than the recovery frame that stays).
            settling = pose.get('settle', {})
            replaced = unshown(pose) | {int(k) for k in settling.get('frames', {}) if int(k) != settling.get('from')}
            rulers = [h['ruler'] for h, i in zip(heads, meta['frame_indices']) if h and i not in replaced] or [h['ruler'] for h in heads if h]
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
    # the median instead (preferring the upright sheets' median). One exception: a
    # stretched-out body (lying, flying flat) does not fit a column at full size, so
    # the model draws it smaller and its visible head correctly asks for a larger
    # scale; that is kept as long as the body stays no longer than the idle allows.
    def rotated(data):
        drawn = [i for i in data['meta']['frame_indices'] if i not in (data['meta'].get('overlap') or [])]
        return any(mode_of(i) != 'feet' for i in drawn)
    upright_scales = [d['head_scale'] for d in sheets if d['measured'] and not rotated(d)]
    clip_median = statistics.median(upright_scales or [d['head_scale'] for d in sheets if d['measured']] or [canon['scale']])
    for data in sheets:
        job, raw, meta, drawings, heads, part_ruler = data['job'], data['raw'], data['meta'], data['drawings'], data['heads'], data['part_ruler']
        scale = data['head_scale']
        method = 'head-ruler'
        drawn = [np.asarray(image) for (_, image), i in zip(drawings, meta['frame_indices']) if i not in (meta.get('overlap') or [])]
        axes = [anatomy.body_axes(a) for a in drawn]
        stretched = max(major / max(1.0, minor) for major, minor in axes) >= 1.8
        if data['measured'] and rotated(data) and stretched and scale > clip_median * 1.12:
            cap = canon['length'] * LENGTH_LIMIT * canon['scale'] / max(major for major, _ in axes)
            if cap < scale:
                scale, method = max(clip_median, cap), 'length-capped'
        elif not data['measured'] or (rotated(data) and abs(scale / clip_median - 1) > 0.12):
            scale = clip_median
            method = 'clip-median'
        elif canon['qa'].get('head_outlier_limit') and abs(scale / clip_median - 1) > canon['qa']['head_outlier_limit']:
            # A face in deep shadow or bowed away measures only the bangs: an upright
            # sheet far off the clip median is a failed measurement, not a drawing scale.
            scale = clip_median
            method = 'clip-median (head not measurable)'
        overlap = meta.get('overlap') or []
        registered = pose.get('register')
        if registered and meta['part'] not in registered.get('parts', [meta['part']]):
            registered = None
        if registered:
            # The body is the referenced drawing (an edit of it): register every drawing
            # on that frame by its lower body; the sheet records the median scale. With
            # "frames" (a frozen copy of this clip's frames, record.json beside them) each
            # drawing is an edit of its own earlier frame and registers on that one.
            if registered.get('frames'):
                folder = ROOT / registered['frames']
                reference_record = read(folder / 'record.json')
            else:
                folder = production(character) / 'imports' / registered['clip']
                reference_record = read(folder.parent / (registered['clip'] + '.json'))

            def placed_on(image, index):
                frame = index if registered.get('frames') else registered['frame']
                reference_frame = Image.open(folder / ('frame-%02d.png' % frame)).convert('RGBA')
                guess = next(f['scale'] for f in reference_record['frames'] if f['frame'] == frame)
                # "band": "upper" matches the head, torso and arms (an edit that moved a leg).
                return register(image, reference_frame, guess, (0.0, 0.55) if registered.get('band') == 'upper' else (0.55, 1.0))
            placed = {index: placed_on(image, index) for (_, image), index in zip(drawings, meta['frame_indices']) if index not in overlap}
            scale = statistics.median(p['registration']['scale'] for _, p in placed.values())
            method = 'registered'
            part_ruler = canon['runtime_ruler'] / scale
        match = pose.get('match_height')
        if match and meta['part'] in match.get('parts', [meta['part']]):
            # The same body as another drawing: the crouching guard is the crouch with the
            # arms raised (they hide the head); a later sheet of a still pose matches an
            # earlier frame of its own clip (already registered above).
            if match['clip'] == clip:
                reference_frame = frames[match['frame']]
            else:
                reference_frame = Image.open(production(character) / 'imports' / match['clip'] / ('frame-%02d.png' % match['frame'])).convert('RGBA')
            target = body_height(np.asarray(reference_frame))
            scale = target / statistics.median(body_height(a) for a in drawn)
            method = 'height-match'
            part_ruler = canon['runtime_ruler'] / scale
        calibrations = []
        for (bbox, image), index in zip(drawings, meta['frame_indices']):
            if index in overlap and index in frames and mode_of(index) != 'lying':
                calibrations.append(body_height(np.asarray(frames[index])) / body_height(np.asarray(image)))
        if calibrations and not registered:
            overlap_scale = statistics.median(calibrations)
            # A redrawn overlap in another pose (more upright, deeper crouch) has another
            # height; when that disagrees with the sheet's own head ruler beyond the
            # character's limit (spec "qa" overlap_head_limit), the head ruler wins.
            limit = canon['qa'].get('overlap_head_limit')
            if limit and data['measured'] and abs(overlap_scale / scale - 1) > limit:
                method = 'head-ruler (overlap pose differs %.0f%%)' % (abs(overlap_scale / scale - 1) * 100)
            else:
                scale = overlap_scale
                method = 'overlap'
        before, after, shifts = data['before'], data['after'], data['shifts']
        parts.append(dict(id=job['id'], source=job['out'], sha256=sha256(raw), ruler=round(part_ruler, 2), scale=round(scale, 4), scale_method=method,
                          resample_vs_idle=round(scale / canon['scale'], 3), palette_shift=shifts,
                          palette_delta_e_before={k: round(palette.delta_e(v, canon['palette'][k]), 2) for k, v in before.items() if k in canon['palette']},
                          palette_delta_e_after={k: round(palette.delta_e(v, canon['palette'][k]), 2) for k, v in after.items() if k in canon['palette']}))
        data.update(final_scale=scale, part_record=parts[-1], placed=[],
                    fixed=bool(registered) or method == 'height-match')
        for (bbox, image), head, index in zip(drawings, heads, meta['frame_indices']):
            if index in overlap:
                continue
            mode = pose.get('anchor', 'feet')
            if index in pose.get('ground_frames', []):
                mode = pose.get('ground_mode', 'feet')
            if registered:
                canvas, placement = placed[index]
            else:
                canvas, placement = place(image, scale, mode, mode == 'lying' and pose.get('lying_centred', False))
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
            # Upright clips stand taller than the idle (5% over Tanjiro's bent-knee guard,
            # 1.6x Zenitsu's low iai stance); stance clips keep the idle's height.
            standing = pose.get('upright_frames')
            if band and mode == 'feet' and (standing is None or index in standing) and not band[0] <= height_ratio <= band[1]:
                flags.append('height %.0f%% of the idle' % (height_ratio * 100))
            placement['height_vs_idle'] = round(height_ratio, 3)
            if pose.get('helper'):
                # Key drawings another clip is assembled from keep their full-resolution
                # drawing, so that clip can deform them before scaling (intro_warp.py).
                drawn_at = production(character) / 'imports' / clip / ('drawing-%02d.png' % index)
                drawn_at.parent.mkdir(parents=True, exist_ok=True)
                image.save(drawn_at)
                placement.update(drawing=rel(drawn_at), exact_scale=float(placement.get('registration', {}).get('exact', scale)))
            frames[index] = canvas
            data['placed'].append((index, image, mode))
            records.append(dict(frame=index, part=job['id'], crop=list(bbox), head_ruler=round(head['ruler'], 2) if head else None,
                                head_box=head['box'] if head else None, ratio_to_sheet=round(ratio, 3) if ratio else None,
                                scale=round(scale, 4), flags=flags, notes=notes, **placement))
    guard_anchor(sheets, frames, records, pose, canon, reference, band)
    size_to(character, sheets, frames, records, pose, canon, idle_height, band)
    settle(sheets, frames, records, pose, idle_height)
    drawn = dict(frames)
    drawn_records = {r['frame']: dict(r) for r in records}
    for target, source in pose.get('copy_frames', {}).items():
        # A held extension shown twice: the model would not draw this frame's arm right
        # (Akaza's rear-hand straights), so it repeats the frame that it did. "clip:N"
        # repeats a frame of another, already processed clip (2D starts and ends on the
        # held crouch, crouch frame 5). Copies read the frames as drawn, so two frames
        # can swap places (Akaza's super rises 8 -> 10 -> 9).
        record = next(r for r in records if r['frame'] == int(target))
        if isinstance(source, str):
            other, number = source.split(':')
            folder = production(character) / 'imports' / other
            frames[int(target)] = Image.open(folder / ('frame-%02d.png' % int(number))).convert('RGBA')
            placed = next(r for r in read(folder.parent / (other + '.json'))['frames'] if r['frame'] == int(number))
            placed = dict(placed, flags=[], height_vs_idle=placed.get('height_vs_idle'))
        else:
            frames[int(target)] = drawn[source].copy()
            placed = drawn_records[source]
        record.update({k: placed.get(k) for k in ('scale', 'offset', 'root_x', 'height_vs_idle', 'flags')},
                      copy_of=source, notes=record['notes'] + ['repeats frame %s' % source])
    for record in records:
        # Frames checked by eye (pose "reviewed": {"8": reason}): the flags become notes.
        reason = pose.get('reviewed', {}).get(str(record['frame']))
        if reason and record['flags']:
            record['notes'] = record['notes'] + ['reviewed (%s): %s' % (reason, '; '.join(record['flags']))]
            record['flags'] = []
    ordered = [frames[i] for i in sorted(frames)]
    save_frames(character, clip, ordered)
    record = dict(character=character, clip=clip, canvas_size=list(CANVAS), feet_anchor=list(ANCHOR),
                  runtime_head_ruler=round(canon['runtime_ruler'], 2), parts=parts, frames=sorted(records, key=lambda r: r['frame']))
    save(production(character) / 'imports' / (clip + '.json'), record)
    return ordered, record


def guard_anchor(sheets, frames, records, pose, canon, reference, band):
    """spec "qa" guard_anchor (Akaza): the head ruler follows the model's head, and the
    model draws the head a different size against the body from sheet to sheet (up to a
    fifth), so moves started or ended visibly larger or smaller than the idle. Re-scales
    each placed sheet so its body matches the idle's (height and silhouette area, the
    square root of its pixel count; the area is what reads as "bigger"):
      guard   a sheet with a guard frame (pose text naming the approved guard; every frame
              of a "stance" clip) scales so those frames match the idle in the geometric
              mean of height and area (a lower, wider guard would match in height alone
              and still look larger);
      clip    other sheets take the clip's median guard correction (1 without guards), then
              their median area is kept under the top of the spec "area" band of the idle
              (unless the torso, head to sash, clearly says the sheet is small); only an upright
              sheet whose area AND torso are both short is enlarged (crouches, sweeps, rolls
              and tucks rightly cover less: enlarging them on area alone blew Akaza's 2D up
              by half); lying sheets are left alone. The largest drawing of such a
              sheet is also kept under spec "area_peak".
    Registered, height-matched and helper sheets are left as they are."""
    config = canon['qa'].get('guard_anchor')
    # A pose sized by its materials ("size_to") skips these rules.
    if not config or pose.get('helper') or pose.get('size_to'):
        return
    texts = pose.get('frames', [])
    guard = set(range(len(texts))) if pose.get('stance') else {i for i, text in enumerate(texts) if any(p in text for p in config['phrases'])}
    belt = anatomy.profile()['materials']['classes'][config.get('belt', 'navy')]
    idle_height = body_height(reference)
    idle_area = float(np.sqrt((reference[:, :, 3] > 150).sum()))
    idle_torso = anatomy.torso(reference, belt)

    def height(index):
        return body_height(np.asarray(frames[index])) / idle_height

    def area(index):
        return float(np.sqrt((np.asarray(frames[index])[:, :, 3] > 150).sum())) / idle_area

    def body(index):
        return float(np.sqrt(height(index) * area(index)))

    def torso(index):
        length = anatomy.torso(np.asarray(frames[index]), belt)
        ratio = length / idle_torso if length else None
        return ratio if ratio and 0.6 < ratio < 1.6 else None

    movable = [d for d in sheets if 'placed' in d and not d['fixed']]
    guards = [body(i) for d in movable for i, _, mode in d['placed'] if i in guard and mode == 'feet']
    clip_factor = 1.0 / statistics.median(guards) if guards else 1.0
    low, high = config['area']
    torso_low, torso_high = config['torso']
    for data in movable:
        placed = data['placed']
        modes = {mode for _, _, mode in placed}
        own = [body(i) for i, _, mode in placed if i in guard and mode == 'feet']
        if own:
            factor, why = 1.0 / statistics.median(own), 'guard frames'
        else:
            factor, why = clip_factor, 'clip guard'
            if placed and 'lying' not in modes:
                size = statistics.median(area(i) for i, _, _ in placed) * factor
                lengths = [t for t in (torso(i) for i, _, _ in placed) if t]
                trunk = statistics.median(lengths) * factor if lengths else None
                if size > high and not (trunk and trunk < torso_low):
                    factor *= high / size
                    why += ' + area %.2f > %.2f' % (size, high)
                elif modes == {'feet'} and size < low and trunk and trunk < torso_low:
                    # A crouch, a sweep or a tuck rightly covers less than the stance, so a
                    # sheet is only enlarged when its torso is short as well (the milder fix).
                    factor *= min(low / size, 1.0 / trunk)
                    why += ' + area %.2f < %.2f, torso %.2f' % (size, low, trunk)
                # No single drawing of the sheet may stand out either (a stretched take-off, a
                # fist raised overhead): spec "area_peak" caps the largest one.
                peak = max(area(i) for i, _, _ in placed) * factor
                if peak > config.get('area_peak', float('inf')):
                    factor *= config['area_peak'] / peak
                    why += ' + peak %.2f' % peak
        rescale(data, factor, why, frames, records, pose, canon, idle_height, band)


def rescale(data, factor, why, frames, records, pose, canon, idle_height, band):
    """Re-places every drawing of one processed sheet at its scale times `factor` and
    updates the sheet's and the frames' records."""
    if abs(factor - 1.0) < 0.002:
        return
    scale = data['final_scale'] * factor
    data['final_scale'] = scale
    part = data['part_record']
    part.update(scale=round(scale, 4), resample_vs_idle=round(scale / canon['scale'], 3),
                scale_method='%s, %s x%.3f' % (part['scale_method'], why, factor))
    for index, image, mode in data['placed']:
        canvas, placement = place(image, scale, mode, mode == 'lying' and pose.get('lying_centred', False))
        frames[index] = canvas
        record = next(r for r in records if r['frame'] == index)
        ratio = body_height(np.asarray(canvas)) / idle_height
        flags = [f for f in record['flags'] if not f.startswith(('height ', 'clipped'))]
        if placement['clipped']:
            flags.append('clipped on canvas')
        standing = pose.get('upright_frames')
        if band and mode == 'feet' and (standing is None or index in standing) and not band[0] <= ratio <= band[1]:
            flags.append('height %.0f%% of the idle' % (ratio * 100))
        record.update(scale=round(scale, 4), flags=flags, height_vs_idle=round(ratio, 3), **{k: placement[k] for k in ('root_x', 'offset', 'clipped')})


def size_to(character, sheets, frames, records, pose, canon, idle_height, band):
    """Pose "size_to": {"clip", "frame", "parts", "ratio"}: every sheet scales so its drawings'
    material areas ("vest", "skin", "uniform" or any spec material class; square roots,
    averaged over the parts) are `ratio` of that frame's. Akaza's 2D: a low sweep's head,
    silhouette and torso all mislead (the model drew one sheet's head a fifth too large; the
    folded legs and hidden sash read small), while the vest and the skin keep their size
    next to the crouch it starts from and returns to.
    "costume" is one part: the uniform and every spec material class together (Zenitsu's
    haori is two hue bands that trade pixels as it turns). With "band": [low, high] instead
    of "ratio", only sheets outside the band move, to its nearest edge (Zenitsu's turn slash:
    the sheets whose heads were drawn large came out 8-15 percent small)."""
    config = pose.get('size_to')
    if not config:
        return
    classes = anatomy.profile()['materials']['classes']

    def part(rgba, name, skin, uniform):
        if name == 'skin':
            return skin
        if name == 'uniform':
            return uniform
        if name == 'costume':
            total = uniform.copy()
            for rule in classes.values():
                total |= anatomy.select(rgba, rule)
            return total
        return anatomy.select(rgba, classes[name])

    def measure(rgba):
        _, skin, uniform = anatomy.masks(rgba)
        return [float(np.sqrt(part(rgba, n, skin, uniform).sum())) for n in config['parts']]
    folder = production(character) / 'imports' / config['clip']
    reference = measure(np.asarray(Image.open(folder / ('frame-%02d.png' % config['frame'])).convert('RGBA')))
    replaced = unshown(pose)
    for data in sheets:
        if 'placed' not in data or data['fixed']:
            continue
        shown = [i for i, _, _ in data['placed'] if i not in replaced]
        if not shown:
            continue
        ratios = [statistics.mean(v / r for v, r in zip(measure(np.asarray(frames[i])), reference)) for i in shown]
        size = statistics.median(ratios)
        if 'band' in config:
            low, high = config['band']
            target = min(max(size, low), high)
            why = 'parts %.2f of %s %d, band %.2f-%.2f' % (size, config['clip'], config['frame'], low, high)
        else:
            target = config.get('ratio', 1.0)
            why = 'parts like %s %d' % (config['clip'], config['frame'])
        rescale(data, target / size, why, frames, records, pose, canon, idle_height, band)


def settle(sheets, frames, records, pose, idle_height):
    """Pose "settle" (Akaza's crouch): frames rebuilt from ONE drawing of the clip, deformed by
    a rig with the feet pinned (spec/akaza-crouch-settle.json: points in that drawing's pixels,
    "poses" of point offsets), so a body sinking into a held pose never changes drawing.
    "frames" maps a frame to its weighted poses ({} is the drawing itself); all of them go
    through the same warp and placement, so they line up to the pixel."""
    config = pose.get('settle')
    if not config:
        return
    rig = read(ROOT / config['rig'])
    source = config['from']
    data = next(d for d in sheets if any(i == source for i, _, _ in d.get('placed', [])))
    image = next(drawing for i, drawing, _ in data['placed'] if i == source)
    if list(image.size) != list(rig['size']):
        raise SystemExit('settle: frame %d is %s px, the rig was made on %s' % (source, image.size, rig['size']))
    scale = data['final_scale']
    _, placement = place(image, scale, 'feet')
    margin = int(rig.get('margin', 40))
    padded = Image.new('RGBA', (image.width + 2 * margin, image.height + 2 * margin))
    padded.alpha_composite(image, (margin, margin))
    names = list(rig['points'])
    base = np.array([rig['points'][name] for name in names], dtype=np.float64) + margin
    at = (placement['offset'][0] - round(margin * scale), placement['offset'][1] - round(margin * scale))
    for key, weights in config['frames'].items():
        index = int(key)
        moved = base.copy()
        for name_pose, weight in weights.items():
            for name, offset in rig['poses'][name_pose].items():
                moved[names.index(name)] += np.array(offset, dtype=np.float64) * weight
        warped = Image.fromarray(idle_warp.warp_points(np.asarray(padded), base, moved, int(rig.get('grid', 6)), float(rig.get('alpha', 1.4))), 'RGBA')
        scaled = warped.resize((round(warped.width * scale), round(warped.height * scale)), Image.Resampling.LANCZOS)
        canvas = Image.new('RGBA', CANVAS)
        canvas.alpha_composite(scaled, (max(0, at[0]), max(0, at[1])), (max(0, -at[0]), max(0, -at[1])))
        frames[index] = canvas
        record = next(r for r in records if r['frame'] == index)
        record.update(scale=round(scale, 4), offset=list(at), height_vs_idle=round(body_height(np.asarray(canvas)) / idle_height, 3),
                      settle=dict(source=source, weights=weights), flags=[f for f in record['flags'] if not f.startswith('height ')],
                      notes=record['notes'] + ['settle: frame %d deformed by %s' % (source, config['rig'])])


def save_frames(character, clip, frames):
    folder = production(character) / 'imports' / clip
    folder.mkdir(parents=True, exist_ok=True)
    for stale in folder.glob('frame-*.png'):
        stale.unlink()
    for index, frame in enumerate(frames):
        frame.save(folder / ('frame-%02d.png' % index))


def process_idle(character, canon):
    """The approved idle loop: warped from the key, so it shares the key's scale exactly."""
    return process_warped(character, canon, 'idle', 'idle-warp', 'idle', cycle=True)


# Every warped clip is resampled from the key padded the same way, so identical
# drawings (the intro's last frames are idle frame 0) give identical canvas pixels.
# spec "warp_pad" overrides it (Zenitsu's hair touches the top of his key and needs
# room above to lift).
WARP_PAD = (20, 0, 130, 0)


def warped_canvas(warped, canon, pad=(0, 0, 0, 0)):
    """A key-space drawing (the key padded by `pad`) on the canvas at the key's own scale
    and placement. Returns (canvas, offset)."""
    margin = canon.get('warp_pad', WARP_PAD)
    root = anatomy.root_x(canon['key']) + margin[0]
    sole = anatomy.sole_y(canon['key']) + margin[1]
    size = (warped.width + margin[0] + margin[2] - pad[0] - pad[2], warped.height + margin[1] + margin[3] - pad[1] - pad[3])
    drawing = Image.new('RGBA', size)
    drawing.alpha_composite(warped, (margin[0] - pad[0], margin[1] - pad[1]))
    scaled = drawing.resize((round(drawing.width * canon['scale']), round(drawing.height * canon['scale'])), Image.Resampling.LANCZOS)
    at = (round(ANCHOR[0] - root * canon['scale']), round(ANCHOR[1] - sole * canon['scale']))
    canvas = Image.new('RGBA', CANVAS)
    canvas.alpha_composite(scaled, at)
    return canvas, at


def process_warped(character, canon, clip, folder_name, prefix, pad=(0, 0, 0, 0), cycle=False):
    """Frames warped from the approved key (idle_warp.py, intro_warp.py): the key's own
    scale and placement. `pad` is what the warp already added around the key."""
    folder = production(character) / 'imports' / folder_name
    paths = sorted(folder.glob(prefix + '-*.png'))
    frames, records = [], []
    for index, path in enumerate(paths):
        canvas, at = warped_canvas(Image.open(path).convert('RGBA'), canon, pad)
        frames.append(canvas)
        records.append(dict(frame=index, source=rel(path), scale=round(canon['scale'], 4), offset=list(at), flags=[]))
    save_frames(character, clip, frames)
    record = dict(character=character, clip=clip, canvas_size=list(CANVAS), feet_anchor=list(ANCHOR),
                  source='output/imagegen/%s-v3/references/approved-idle-candidate.png' % character, frames=records)
    if cycle:
        record['cycle'] = True
    save(production(character) / 'imports' / (clip + '.json'), record)
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
        warp = poses.get(clip, {}).get('warp')
        if warp and warp.get('assembled'):
            # Key drawings plus warps of the approved key (intro_warp.py builds the canvas frames).
            import intro_warp
            frames = intro_warp.build(args.character, clip=clip, spec_path=warp.get('spec'))
            review(args.character, clip, frames, dict(frames=[dict(ratio_to_sheet=1.0, flags=[]) for _ in frames]), 9,
                   Image.open(production(args.character) / 'imports/idle/frame-00.png').convert('RGBA'))
            print('%s: %d frames assembled from %s' % (clip, len(frames), warp['tool']))
            continue
        if warp:
            pad = read(production(args.character) / 'imports' / (warp['folder'] + '.json'))['pad']
            frames, record = process_warped(args.character, canon, clip, warp['folder'], warp['prefix'], pad)
            review(args.character, clip, frames, dict(frames=[dict(ratio_to_sheet=1.0, flags=[]) for _ in frames]), 12,
                   Image.open(production(args.character) / 'imports/idle/frame-00.png').convert('RGBA'))
            print('%s: %d frames warped from the approved key' % (clip, len(frames)))
            continue
        clip_jobs = [j for j in jobs if j.get('metadata', {}).get('clip') == clip and j['id'].startswith(args.character + '-v3-' + clip + '-p')
                     and not j.get('superseded_by')]
        if not clip_jobs or not all((ROOT / j['out']).exists() for j in clip_jobs):
            print('skip', clip, '(sheets missing)')
            continue
        pose = poses.get(clip, {})
        # "upright_frames" limits the standing check to the frames that stand (a clip rising from a low stance).
        band = (canon['qa'].get('upright') if pose.get('upright') or pose.get('upright_frames')
                else canon['qa'].get('stance') if pose.get('stance') else None)
        frames, record = process_clip(args.character, clip, clip_jobs, canon, band, poses.get(clip))
        reference = Image.open(production(args.character) / 'imports/idle/frame-00.png').convert('RGBA')
        fps = atlas['clips'].get(clip, {}).get('fps') or poses.get(clip, {}).get('new', {}).get('fps', 12)
        review(args.character, clip, frames, record, fps, reference)
        flagged = [r for r in record['frames'] if r['flags']]
        print('%s: %d frames, sheet scales %s, flagged %d' % (clip, len(frames), [p['resample_vs_idle'] for p in record['parts']], len(flagged)))
        for r in flagged:
            print('   frame', r['frame'], r['flags'])


if __name__ == '__main__':
    main()
