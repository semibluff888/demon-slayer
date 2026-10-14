"""Round intro assembled from key drawings that share the approved guard's body.

The intro is one continuous action: sheathed and eyes closed in full-focus breathing,
eyes snap open, a fast draw, and the drawn blade settles into the guard. Every drawing
keeps the approved body, so the stance, proportions and line weight never jump:

  key frames  edits of idle frame 0 (pose "intro_keys", helper clip: only the arms,
              katana and eyes changed), registered onto idle frame 0 by the lower body
              (process.py). Each is deformed at full resolution before scaling, with
              displacements given in idle-key pixels and carried through the key's
              registration, so the breath matches the idle loop's anatomy;
  warp frames MLS warps of the approved key itself (the hands settle from the draw
              into the guard); the sword turns and moves as one rigid piece with the
              hands, so the blade never bends;
  {}          idle frame 0 exactly (the same pixels as the idle loop's first frame).

Spec (spec/<id>-intro-rig.json):
{
  "idle_rig": "tanjiro-idle-rig.json", "keys": ["intro_keys", "intro_cut"], "pad": [left, top, right, bottom],
  "key_motions": {"inhale": {"chest": [dx, dy], ...}},       # on key drawings
  "poses": {"reach": {"hilt": [dx, dy], ...}},                # on the approved key
  "sword": {"pivot": "hilt", "points": ["guard", "blade_mid", "blade_tip"], "extra": 8, "rotate": {"reach": -4}},
  "timeline": [{"key": 0}, {"key": 0, "inhale": 0.5}, {"key": "intro_cut:0"}, ..., {"reach": 1.0}, ..., {}]
}
A key is drawing N of the first key clip, or "clip:N" of any of them.

Usage: python tools/art_v3/intro_warp.py [--character tanjiro] [--preview GIF]
Writes output/imagegen/<id>-v3/imports/round_intro/frame-NN.png and round_intro.json.
"""
import argparse

import numpy as np
from PIL import Image

from common import ROOT, production, read, rel, save
import idle_warp
import process

SPEC = ROOT / 'tools/art_v3/spec'
# Arm and sword points of the guard: the key drawings hold their hands elsewhere.
ARM_POINTS = ('hilt', 'guard', 'blade_mid', 'blade_tip', 'elbow_back', 'sleeve_back')


def warp_poses(spec, rig):
    """Control points of the padded approved key and their positions in every warp frame."""
    left, top = spec['pad'][0], spec['pad'][1]
    names = list(rig['points'])
    base, start = idle_warp.displaced(rig, 0.0)  # idle frame 0: the pose the intro ends on
    sword = spec['sword']
    pivot = names.index(sword['pivot'])
    rigid = [names.index(name) for name in sword['points']]
    guard, tip = base[rigid[0]], base[rigid[-1]]
    extra = np.array([guard + (tip - guard) * (n + 1) / (sword['extra'] + 1) for n in range(sword['extra'])])
    base = np.vstack([base, extra])
    start = np.vstack([start, extra + (start[pivot] - base[pivot])])
    rigid += list(range(len(names), len(base)))
    shift = np.array([left, top], dtype=np.float64)
    frames = []
    for weights in spec['timeline']:
        if 'key' in weights:
            frames.append(None)
            continue
        moved = start.copy()
        for pose, weight in weights.items():
            for name, offset in spec['poses'][pose].items():
                moved[names.index(name)] += np.array(offset, dtype=np.float64) * weight
        angle = np.radians(sum(sword['rotate'].get(pose, 0.0) * weight for pose, weight in weights.items()))
        turn = np.array([[np.cos(angle), -np.sin(angle)], [np.sin(angle), np.cos(angle)]])
        for index in rigid:
            moved[index] = moved[pivot] + turn @ (start[index] - start[pivot])
        frames.append(None if not weights else moved + shift)
    return base + shift, frames


def paste(drawing, scale, offset):
    """The registered key drawing on the canvas (process.register's placement)."""
    scaled = drawing.resize((max(1, round(drawing.width * scale)), max(1, round(drawing.height * scale))), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', process.CANVAS)
    canvas.alpha_composite(scaled, (max(0, offset[0]), max(0, offset[1])), (max(0, -offset[0]), max(0, -offset[1])))
    return canvas


def key_frame(record, weights, spec, rig, to_canvas, grid, alpha):
    """One key drawing deformed by the weighted key motions (idle-key displacements)."""
    drawing = Image.open(ROOT / record['drawing']).convert('RGBA')
    scale, offset = record['exact_scale'], np.array(record['offset'], dtype=np.float64)
    # Every key frame takes the same path (a still one is an identity warp), so
    # consecutive frames of one drawing never shift by a rounding pixel.
    motions = {name: weight for name, weight in weights.items() if name != 'key'}
    _, start = idle_warp.displaced(rig, 0.0)
    names = [name for name in rig['points'] if name not in ARM_POINTS]
    points = np.array([start[list(rig['points']).index(name)] for name in names])
    # idle key -> canvas -> this drawing's own pixels (its registration is a scale and a shift)
    base = (to_canvas(points) - offset) / scale
    moved = base.copy()
    # Key pixels -> drawing pixels: the drawing is scaled by canon / scale relative to the key.
    to_drawing = to_canvas.scale / scale
    for motion, weight in motions.items():
        for name, delta in spec['key_motions'].get(motion, {}).items():
            moved[names.index(name)] += np.array(delta, dtype=np.float64) * weight * to_drawing
    # Room for the hair and haori to move past the cropped drawing's edge; the same for
    # every key frame (see above).
    margin = 24
    padded = Image.new('RGBA', (drawing.width + 2 * margin, drawing.height + 2 * margin))
    padded.alpha_composite(drawing, (margin, margin))
    warped = idle_warp.warp_points(np.asarray(padded), base + margin, moved + margin, grid, alpha)
    return paste(Image.fromarray(warped, 'RGBA'), scale, (round(offset[0] - margin * scale), round(offset[1] - margin * scale)))


class KeyToCanvas:
    """Idle-key pixels -> canvas pixels (where idle frame 0 sits on the canvas)."""

    def __init__(self, canon):
        self.scale = canon['scale']
        root = process.anatomy.root_x(canon['key']) + process.WARP_PAD[0]
        sole = process.anatomy.sole_y(canon['key']) + process.WARP_PAD[1]
        self.at = np.array([round(process.ANCHOR[0] - root * self.scale), round(process.ANCHOR[1] - sole * self.scale)], dtype=np.float64)
        self.pad = np.array(process.WARP_PAD[:2], dtype=np.float64)

    def __call__(self, points):
        return (np.asarray(points, dtype=np.float64) + self.pad) * self.scale + self.at


def build(character, preview=None):
    spec = read(SPEC / ('%s-intro-rig.json' % character))
    rig = read(SPEC / spec['idle_rig'])
    canon = process.canonical(character)
    key = Image.open(ROOT / rig['key']).convert('RGBA')
    left, top, right, bottom = spec['pad']
    padded = Image.new('RGBA', (key.width + left + right, key.height + top + bottom))
    padded.alpha_composite(key, (left, top))
    image = np.asarray(padded)
    base, warps = warp_poses(spec, rig)
    clips = spec['keys'] if isinstance(spec['keys'], list) else [spec['keys']]
    key_records = {}
    for clip in clips:
        for record in read(production(character) / 'imports' / (clip + '.json'))['frames']:
            key_records['%s:%d' % (clip, record['frame'])] = record
    to_canvas = KeyToCanvas(canon)
    grid, alpha = int(rig.get('grid', 6)), float(rig.get('alpha', 1.4))
    frames, records = [], []
    rest = None
    for index, (weights, moved) in enumerate(zip(spec['timeline'], warps)):
        if 'key' in weights:
            name = weights['key']
            record = key_records[name if isinstance(name, str) else '%s:%d' % (clips[0], name)]
            frame = key_frame(record, weights, spec, rig, to_canvas, grid, alpha)
            source = record['drawing']
        elif moved is None:
            # The handover frames are idle frame 0 exactly (same warp and placement as the idle loop).
            if rest is None:
                still = Image.new('RGBA', padded.size)
                still.alpha_composite(Image.fromarray(idle_warp.warp(np.asarray(key), rig, 0.0), 'RGBA'), (left, top))
                rest, _ = process.warped_canvas(still, canon, spec['pad'])
            frame, source = rest, rig['key']
        else:
            warped = Image.fromarray(idle_warp.warp_points(image, base, moved, grid, alpha), 'RGBA')
            frame, _ = process.warped_canvas(warped, canon, spec['pad'])
            source = rig['key']
        frames.append(frame)
        records.append(dict(frame=index, source=source, weights=weights, flags=[]))
    process.save_frames(character, 'round_intro', frames)
    save(production(character) / 'imports/round_intro.json',
         dict(character=character, clip='round_intro', canvas_size=list(process.CANVAS), feet_anchor=list(process.ANCHOR),
              source=rig['key'], keys=[rel(production(character) / 'imports' / (clip + '.json')) for clip in clips],
              spec=rel(SPEC / ('%s-intro-rig.json' % character)), frames=records))
    if preview:
        box = None
        for frame in frames:
            b = frame.getbbox()
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
        backdrop = []
        for frame in frames:
            canvas = Image.new('RGBA', process.CANVAS, (27, 34, 51, 255))
            canvas.alpha_composite(frame)
            backdrop.append(canvas.crop(box).convert('RGB'))
        # 120 ticks over the clip's frames: about 111 ms per drawing.
        backdrop[0].save(preview, save_all=True, append_images=backdrop[1:], duration=111, loop=0)
    return frames


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--character', default='tanjiro')
    parser.add_argument('--preview')
    args = parser.parse_args()
    frames = build(args.character, args.preview)
    print('intro frames:', len(frames), '->', production(args.character) / 'imports/round_intro')


if __name__ == '__main__':
    main()
