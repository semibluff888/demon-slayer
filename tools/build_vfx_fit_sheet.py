"""Fit effect shapes to the drawn frames: fighter-local coordinates of a character's clips.

Effects are drawn in fighter-local units (feet at 0,0, +x forward, 1 unit = 1 world px
at camera zoom 1), the atlas in canvas pixels; canonical_height / source_height converts.

  python tools/build_vfx_fit_sheet.py grid akaza artifacts/akaza-v3/review/grid.jpg stand_light:2,3 stand_heavy
      draws the frames on a 10-unit grid (labels every 50) so curves and anchors can be read off;
  python tools/build_vfx_fit_sheet.py tips akaza stand_light body_stand_heavy
      prints per frame the forward-most point (fist or foot), the top and the
      up-forward extreme of the silhouette, in local units.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


def atlas(character):
    data = json.loads((ROOT / 'art/characters' / character / 'atlas.json').read_text(encoding='utf-8'))
    return data, data['canonical_height'] / data['source_height']


def frame_pixels(character, entry, pages):
    path = ROOT / 'art/characters' / character / entry['texture']
    if path not in pages:
        pages[path] = Image.open(path).convert('RGBA')
    x, y, w, h = entry['region']
    return pages[path].crop((x, y, x + w, y + h))


def grid(character, out, specs):
    data, scale = atlas(character)
    canvas_w, canvas_h = data['canvas_size']
    ax, ay = data['feet_anchor']
    unit = 1.0 / scale
    pages = {}
    tiles = []
    for spec in specs:
        clip, _, picks = spec.partition(':')
        info = data['clips'][clip]
        indices = [int(v) for v in picks.split(',')] if picks else range(len(info['frames']))
        for i in indices:
            entry = info['frames'][i]
            tile = Image.new('RGBA', (canvas_w, canvas_h), (24, 26, 34, 255))
            draw = ImageDraw.Draw(tile)
            for gx in range(-60, 141, 10):
                px = ax + gx * unit
                draw.line([(px, 0), (px, canvas_h)], fill=(150, 170, 210, 255) if gx % 50 == 0 else (70, 90, 120, 255))
            for gy in range(-120, 11, 10):
                py = ay + gy * unit
                draw.line([(0, py), (canvas_w, py)], fill=(150, 170, 210, 255) if gy % 50 == 0 else (70, 90, 120, 255))
            tile.alpha_composite(frame_pixels(character, entry, pages), tuple(entry['offset']))
            draw.ellipse([ax - 5, ay - 5, ax + 5, ay + 5], fill=(255, 80, 80, 255))
            draw.text((6, 6), '%s #%d (phase_breaks %s)' % (clip, i, info.get('phase_breaks')), fill=(255, 230, 160, 255))
            for gx in range(-50, 141, 50):
                draw.text((ax + gx * unit + 2, 24), str(gx), fill=(200, 220, 255, 255))
            for gy in range(-100, 1, 50):
                draw.text((4, ay + gy * unit + 2), str(gy), fill=(200, 220, 255, 255))
            tiles.append(tile.convert('RGB').resize((canvas_w // 2, canvas_h // 2)))
    columns = 4
    width, height = tiles[0].size
    sheet = Image.new('RGB', (width * columns, height * ((len(tiles) + columns - 1) // columns)))
    for k, tile in enumerate(tiles):
        sheet.paste(tile, ((k % columns) * width, (k // columns) * height))
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, quality=88)
    print(out, sheet.size)


def tips(character, clips):
    data, scale = atlas(character)
    ax, ay = data['feet_anchor']
    pages = {}
    for clip in clips:
        info = data['clips'][clip]
        print('==', clip, 'frames', len(info['frames']), 'phase_breaks', info.get('phase_breaks'))
        for i, entry in enumerate(info['frames']):
            alpha = np.asarray(frame_pixels(character, entry, pages))[:, :, 3] > 128
            ys, xs = np.nonzero(alpha)
            lx = (xs + entry['offset'][0] - ax) * scale
            ly = (ys + entry['offset'][1] - ay) * scale
            right = lx.max()
            top = ly.min()
            k = int(np.argmax(lx - ly * 0.8))
            print('  #%d front (%.0f, %.0f) | top y %.0f at x %.0f | up-forward (%.0f, %.0f) | box x[%.0f, %.0f] y[%.0f, %.0f]' % (
                i, right, ly[lx > right - 2.0].mean(), top, lx[ly < top + 2.0].mean(), lx[k], ly[k], lx.min(), lx.max(), ly.min(), ly.max()))


if __name__ == '__main__':
    if len(sys.argv) < 3 or sys.argv[1] not in ('grid', 'tips'):
        sys.exit(__doc__)
    if sys.argv[1] == 'grid':
        grid(sys.argv[2], sys.argv[3], sys.argv[4:])
    else:
        tips(sys.argv[2], sys.argv[3:])
