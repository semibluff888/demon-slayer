"""Imports Tanjiro's generated VFX sources (output/imagegen/tanjiro-vfx-v1/raw)
into game textures under art/effects/tanjiro/, with provenance.

  band    full-width strip -> cropped to its rows, made horizontally seamless
  sprite  single element -> cropped to its alpha bounds
  sheet   4x4 element grid -> each element re-centred in a uniform cell

Backgrounds are keyed automatically: real alpha is kept, flat magenta is
un-mixed, flat black is treated as emitted light (alpha = brightness).
A tileable erosion noise is generated procedurally.

  python tools/build_tanjiro_vfx_art.py
"""
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'output/imagegen/tanjiro-vfx-v1'
OUT = ROOT / 'art/effects/tanjiro'
LANCZOS = Image.Resampling.LANCZOS

ASSETS = {
    'water-strands': {'raw': 'water-strands.png', 'kind': 'band', 'size': [2048, 320]},
    'fire-strands': {'raw': 'fire-strands.png', 'kind': 'band', 'size': [2048, 320]},
    'water-crescent': {'raw': 'water-crescent.png', 'kind': 'sprite', 'max': 1024},
    'water-crescent-heavy': {'raw': 'water-crescent-v2.png', 'kind': 'sprite', 'max': 1024},
    'water-impact': {'raw': 'water-impact.png', 'kind': 'sprite', 'max': 1024},
    'water-foam': {'raw': 'water-foam-sheet.png', 'kind': 'sheet', 'grid': [4, 4], 'cell': 256},
    'fire-petals': {'raw': 'fire-petals-sheet-v2.png', 'kind': 'sheet', 'grid': [4, 4], 'cell': 256},
    'fire-wisps': {'raw': 'fire-petals-sheet.png', 'kind': 'sheet', 'grid': [4, 4], 'cell': 256},
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def matte(image):
    """Returns straight-alpha RGBA float32 in 0..1 and the key that was used."""
    rgba = np.asarray(image.convert('RGBA'), dtype=np.float32) / 255.0
    if rgba[..., 3].min() < 0.98:
        return rgba, 'alpha'
    rgb = rgba[..., :3]
    corners = np.array([rgb[4, 4], rgb[4, -5], rgb[-5, 4], rgb[-5, -5]])
    if (corners[:, 0] > 0.75).all() and (corners[:, 1] < 0.25).all() and (corners[:, 2] > 0.75).all():
        key = np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]
        alpha = np.clip(1 - (key - 48 / 255) * 3.5, 0, 1)
        clean = (rgb - np.array([1, 0, 1], np.float32) * (1 - alpha[..., None])) / np.maximum(alpha[..., None], 1 / 255)
        return np.dstack((np.clip(clean, 0, 1), alpha)), 'magenta'
    if (corners.max(axis=1) < 0.08).all():
        alpha = rgb.max(axis=2)
        alpha = np.where(alpha < 0.03, 0, alpha)
        clean = rgb / np.maximum(alpha[..., None], 1 / 255)
        return np.dstack((np.clip(clean, 0, 1), alpha)), 'black'
    raise ValueError('unrecognised background')


def to_image(rgba):
    return Image.fromarray(np.uint8(np.clip(rgba * 255 + 0.5, 0, 255)), 'RGBA')


def resize(rgba, size):
    """Premultiplied resize so transparent pixels never bleed dark fringes."""
    pre = np.dstack((rgba[..., :3] * rgba[..., 3:], rgba[..., 3:]))
    out = cv2.resize(pre, tuple(size), interpolation=cv2.INTER_AREA if size[0] < rgba.shape[1] else cv2.INTER_CUBIC)
    out = np.clip(out, 0, 1)
    rgb = out[..., :3] / np.maximum(out[..., 3:], 1e-4)
    return np.dstack((np.clip(rgb, 0, 1), out[..., 3]))


def bounds(alpha, threshold=0.04):
    ys, xs = np.nonzero(alpha > threshold)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def band(rgba, size):
    alpha = rgba[..., 3]
    rows = np.nonzero((alpha > 0.04).mean(axis=1) > 0.01)[0]
    pad = int((rows[-1] - rows[0]) * 0.04)
    top, bottom = max(0, rows[0] - pad), min(alpha.shape[0], rows[-1] + 1 + pad)
    strip = rgba[top:bottom]
    width, height = size
    overlap = int(width * 0.18)
    strip = resize(strip, (width + overlap, height))
    pre = np.dstack((strip[..., :3] * strip[..., 3:], strip[..., 3:]))
    # Cross-fade the head into the tail: out[x] continues from out[width - 1].
    out = pre[:, :width].copy()
    ramp = (np.arange(overlap, dtype=np.float32) / overlap)[None, :, None]
    out[:, :overlap] = pre[:, width:width + overlap] * (1 - ramp) + pre[:, :overlap] * ramp
    rgb = out[..., :3] / np.maximum(out[..., 3:], 1e-4)
    return np.dstack((np.clip(rgb, 0, 1), out[..., 3]))


def sprite(rgba, max_side):
    x0, y0, x1, y1 = bounds(rgba[..., 3])
    pad = int(max(x1 - x0, y1 - y0) * 0.03)
    h, w = rgba.shape[:2]
    crop = rgba[max(0, y0 - pad):min(h, y1 + pad), max(0, x0 - pad):min(w, x1 + pad)]
    scale = min(1.0, max_side / max(crop.shape[:2]))
    if scale < 1.0:
        crop = resize(crop, (round(crop.shape[1] * scale), round(crop.shape[0] * scale)))
    return crop


def sheet(rgba, grid, cell):
    columns, rows = grid
    h, w = rgba.shape[:2]
    mask = (rgba[..., 3] > 0.06).astype(np.uint8)
    merged = cv2.dilate(mask, np.ones((9, 9), np.uint8))
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(merged, 8)
    groups = [[] for _ in range(columns * rows)]
    for label in range(1, count):
        if stats[label, cv2.CC_STAT_AREA] < 30:
            continue
        cx, cy = centroids[label]
        index = min(rows - 1, int(cy / h * rows)) * columns + min(columns - 1, int(cx / w * columns))
        groups[index].append(label)
    out = np.zeros((rows * cell, columns * cell, 4), np.float32)
    cells = []
    for index, labels_in_cell in enumerate(groups):
        if not labels_in_cell:
            cells.append(None)
            continue
        region = np.isin(labels, labels_in_cell) & (mask > 0)
        x0, y0, x1, y1 = bounds(region.astype(np.float32), 0.5)
        crop = rgba[y0:y1, x0:x1].copy()
        crop[..., 3] *= region[y0:y1, x0:x1]
        fit = cell * 0.9 / max(crop.shape[:2])
        crop = resize(crop, (max(1, round(crop.shape[1] * fit)), max(1, round(crop.shape[0] * fit))))
        ch, cw = crop.shape[:2]
        oy = (index // columns) * cell + (cell - ch) // 2
        ox = (index % columns) * cell + (cell - cw) // 2
        out[oy:oy + ch, ox:ox + cw] = crop
        cells.append({'aspect': round(cw / ch, 3)})
    return out, cells


def noise(size=256, octaves=5, seed=11):
    """Tileable fractal value noise in 0..1."""
    rng = np.random.default_rng(seed)
    total = np.zeros((size, size), np.float32)
    amplitude, weight = 1.0, 0.0
    for octave in range(octaves):
        cells = 4 * 2 ** octave
        lattice = rng.random((cells, cells)).astype(np.float32)
        grid = np.arange(size, dtype=np.float32) * cells / size
        i0 = np.floor(grid).astype(int) % cells
        i1 = (i0 + 1) % cells
        t = grid - np.floor(grid)
        t = t * t * (3 - 2 * t)
        rows = lattice[i0][:, i0] * (1 - t)[None, :] + lattice[i0][:, i1] * t[None, :]
        rows2 = lattice[i1][:, i0] * (1 - t)[None, :] + lattice[i1][:, i1] * t[None, :]
        total += (rows * (1 - t)[:, None] + rows2 * t[:, None]) * amplitude
        weight += amplitude
        amplitude *= 0.5
    total /= weight
    total = (total - total.min()) / (total.max() - total.min())
    return total


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {'note': 'Generated with gpt-image-2 through the CPA endpoint; imported by tools/build_tanjiro_vfx_art.py.', 'assets': {}}
    for name, spec in ASSETS.items():
        raw = SRC / 'raw' / spec['raw']
        source, key = matte(Image.open(raw))
        info = {'source': raw.relative_to(ROOT).as_posix(), 'source_sha256': digest(raw), 'kind': spec['kind'], 'key': key,
                'prompt': (SRC / 'prompts' / (Path(spec['raw']).stem + '.txt')).relative_to(ROOT).as_posix()}
        if spec['kind'] == 'band':
            result = band(source, spec['size'])
        elif spec['kind'] == 'sprite':
            result = sprite(source, spec['max'])
        else:
            result, cells = sheet(source, spec['grid'], spec['cell'])
            info.update({'grid': spec['grid'], 'cells': cells})
        target = OUT / (name + '.png')
        to_image(result).save(target)
        info.update({'size': [result.shape[1], result.shape[0]], 'sha256': digest(target)})
        manifest['assets'][name] = info
        print(f'{name:22s} {key:8s} {result.shape[1]}x{result.shape[0]}')
    Image.fromarray(np.uint8(noise() * 255), 'L').save(OUT / 'noise.png')
    manifest['assets']['noise'] = {'kind': 'procedural', 'size': [256, 256], 'sha256': digest(OUT / 'noise.png')}
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
