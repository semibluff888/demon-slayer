"""Builds Akaza's procedural effect textures into art/effects/akaza/ (deterministic).

  shock-cyan.png, shock-azure.png
      the contact burst after the Hinokami Chronicles look: a full, fluffy ball
      round a white-hot core whose rim frays into short, blunt, soft-edged
      tongues (not a sharp sea urchin), light at the centre with a faint deep
      outline. 4 variants (columns) x 2 stages (rows): row 0 is
      the dense first frame, row 1 the same burst breaking up (thinner, broken
      strands, a smaller core), which the game cross-fades into. 256 px cells.
  rocks.png
      4 x 4 cells of angular rock chunks, flat-shaded facets lit from the upper
      left with a dark outline, grey so the game tints them (slate rubble, rock lit
      blue by the blast). 64 px cells.

  python tools/build_akaza_vfx_art.py [--out DIR] [--preview out.png]

Rendered at twice the size and reduced with Lanczos. Import settings: mipmaps on
(see the .import files next to them).
"""
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'art/effects/akaza'
LANCZOS = Image.Resampling.LANCZOS
CELL = 256
SS = 2

# Ramps from the reference (docs/vfx/akaza-reference.md): edge, deep, body, light, core.
PALETTES = {
    'cyan': ['#0d2473', '#225ddc', '#59c8f5', '#bff2ff', '#ffffff'],
    # Awakened: the royal blue of the Infinity Castle flames (the first blue-violet
    # ramp '#1e1060', '#4b33e0', '#8d7be7', '#ddd5ff' read as a washed-out lilac).
    'azure': ['#0a1a66', '#1f40d9', '#5c8cff', '#cfe0ff', '#ffffff'],
}


def rgb(hex_colour):
    return np.array([int(hex_colour[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


def ramp(palette, heat):
    """Body colour by heat 0..1: deep -> body -> light -> white."""
    stops = [0.0, 0.22, 0.55, 0.88]
    colours = [rgb(c) for c in palette[1:]]
    out = np.zeros(heat.shape + (3,), np.float32)
    for i in range(len(stops) - 1):
        lo, hi = stops[i], stops[i + 1]
        u = np.clip((heat - lo) / (hi - lo), 0.0, 1.0)[..., None]
        band = (heat >= lo) & (heat < hi) if i < len(stops) - 2 else heat >= lo
        out = np.where(band[..., None], colours[i] * (1 - u) + colours[i + 1] * u, out)
    return out


def strand(mask, centre, angle, inner, length, width, bend, taper=1.5):
    """One sharp, tapering spike from radius `inner` to `length`, bent a little."""
    steps = 14
    left, right = [], []
    for k in range(steps + 1):
        t = k / steps
        r = inner + (length - inner) * t
        a = angle + bend * t * t
        axis = np.array([np.cos(a), np.sin(a)])
        side = np.array([-axis[1], axis[0]])
        w = width * (1.0 - t) ** taper
        p = centre + axis * r
        left.append(p + side * w)
        right.append(p - side * w)
    poly = np.array(left + right[::-1], np.float32)
    cv2.fillPoly(mask, [np.round(poly * 16).astype(np.int32)], 1.0, cv2.LINE_AA, shift=4)


def burst(seed, stage, palette):
    rng = np.random.default_rng(1000 + seed)
    size = CELL * SS
    centre = np.array([size / 2, size / 2], np.float32)
    reach = size * 0.46
    dense = np.zeros((size, size), np.float32)
    # Short, blunt tongues packed round the centre: they fray the rim of the
    # ball rather than stick out of it.
    count = 170
    angles = np.sort(rng.uniform(0, 2 * np.pi, count))
    # Low lobes make the silhouette a lumpy clump rather than a disc.
    phase = rng.uniform(0, 2 * np.pi, 2)
    lobes = lambda a: 1.0 + 0.09 * np.sin(3 * a + phase[0]) + 0.06 * np.sin(5 * a + phase[1])
    for n in range(count):
        layer = np.zeros_like(dense)
        length = reach * (0.5 + 0.32 * rng.uniform() ** 1.2)
        if rng.uniform() < 0.06:
            length = reach * rng.uniform(0.8, 0.9)
        length = min(length * lobes(angles[n]), reach)
        width = reach * rng.uniform(0.045, 0.08) * (0.8 + 0.4 * length / reach)
        inner = reach * 0.05
        if stage == 1:
            # Breaking up: fewer, a little thinner and longer.
            if rng.uniform() < 0.3:
                continue
            length *= rng.uniform(1.0, 1.1)
            width *= 0.72
            inner = reach * rng.uniform(0.05, 0.12)
        strand(layer, centre, angles[n] + rng.uniform(-0.03, 0.03), inner, length, width, rng.uniform(-0.08, 0.08), 0.85)
        dense = np.maximum(dense, layer * rng.uniform(0.8, 1.0))
    # A few hair-thin wisps just past the rim.
    for n in range(20):
        layer = np.zeros_like(dense)
        a = rng.uniform(0, 2 * np.pi)
        length = min(reach * rng.uniform(0.55, 0.8) * lobes(a) * (1.1 if stage == 1 else 1.0), reach * 0.95)
        strand(layer, centre, a, reach * 0.1, length, reach * rng.uniform(0.008, 0.016), rng.uniform(-0.05, 0.05), 1.0)
        dense = np.maximum(dense, layer * rng.uniform(0.6, 0.9))
    # The body binding the spikes together: a bumpy disc (small once it breaks up).
    body = np.zeros_like(dense)
    points = []
    for k in range(36):
        a = 2 * np.pi * k / 36
        points.append(centre + np.array([np.cos(a), np.sin(a)]) * reach * (0.48 if stage == 0 else 0.3) * (1.0 + (lobes(a) - 1.0) * 0.5) * rng.uniform(0.88, 1.12))
    cv2.fillPoly(body, [np.round(np.array(points) * 16).astype(np.int32)], 1.0, cv2.LINE_AA, shift=4)
    mask = np.maximum(dense, body)
    keep = np.ones_like(mask)
    if stage == 1:
        # Breaking up: the whole burst thins out.
        keep *= 0.85
    # Bright fine streaks along the spikes give the fluffy texture.
    streaks = np.zeros_like(mask)
    for n in range(70):
        a = rng.uniform(0, 2 * np.pi)
        r0 = reach * rng.uniform(0.05, 0.25)
        r1 = reach * rng.uniform(0.45, 0.85)
        p0 = centre + np.array([np.cos(a), np.sin(a)]) * r0
        p1 = centre + np.array([np.cos(a), np.sin(a)]) * r1
        cv2.line(streaks, tuple(int(v) for v in p0), tuple(int(v) for v in p1), rng.uniform(0.4, 1.0), int(rng.integers(1, 3)), cv2.LINE_AA)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dist = np.hypot(xx - centre[0], yy - centre[1]) / reach
    soft = cv2.GaussianBlur(mask, (0, 0), 6.0)
    core = np.clip(1.0 - dist / (0.24 if stage == 0 else 0.15), 0.0, 1.0) ** 0.8
    heat = np.clip(soft * 0.5 + core * 0.6 + streaks * mask * 0.4 - dist * 0.2, 0.0, 1.0)
    if stage == 1:
        heat *= 0.8
    colour = ramp(palette, heat)
    # A deep outline round the spikes (the anime edge), only outside the fill.
    grown = cv2.dilate(mask, np.ones((5, 5), np.uint8))
    edge = np.clip(grown - mask, 0.0, 1.0)
    edge = cv2.GaussianBlur(edge, (0, 0), 1.6)
    alpha = np.clip(mask * 1.15, 0.0, 1.0)
    # The fill thins toward the tips so the burst reads soft, not glassy.
    alpha *= np.clip(1.45 - dist * 1.0, 0.25, 1.0) * keep
    edge_alpha = edge * 0.45 * (0.75 if stage == 1 else 1.0) * keep
    edge_colour = rgb(palette[0]) * 0.5 + rgb(palette[1]) * 0.5
    out_alpha = alpha + edge_alpha * (1.0 - alpha)
    out_rgb = (colour * alpha[..., None] + edge_colour * (edge_alpha * (1.0 - alpha))[..., None]) / np.maximum(out_alpha[..., None], 1e-4)
    # A faint halo so the silhouette never ends on a hard step.
    halo = cv2.GaussianBlur(mask, (0, 0), 14.0) * 0.3 * keep
    halo_alpha = halo * (1.0 - out_alpha)
    final_alpha = out_alpha + halo_alpha
    final_rgb = (out_rgb * out_alpha[..., None] + rgb(palette[2]) * halo_alpha[..., None]) / np.maximum(final_alpha[..., None], 1e-4)
    image = np.dstack([final_rgb, final_alpha])
    image = (np.clip(image, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(image, 'RGBA').resize((CELL, CELL), LANCZOS)


def rock(seed):
    rng = np.random.default_rng(5000 + seed)
    size = 64 * SS
    centre = np.array([size / 2, size / 2 + 2], np.float32)
    count = int(rng.integers(6, 10))
    angles = np.sort((np.arange(count) + rng.uniform(-0.3, 0.3, count)) * 2 * np.pi / count)
    # Some chunks, some flatter broken slabs.
    stretch = rng.uniform(0.5, 0.95)
    radii = rng.uniform(0.7, 1.0, count) * size * 0.42
    corners = [centre + np.array([np.cos(a), np.sin(a) * stretch]) * r for a, r in zip(angles, radii)]
    # Three large flat faces meeting at a ridge point: a lit top, a front and a dark side.
    apex = centre + np.array([rng.uniform(-0.2, 0.15), rng.uniform(-0.3, -0.05) * stretch]) * size * 0.42
    splits = sorted({int(round(v)) % count for v in (np.array([0.0, 1.0, 2.0]) + rng.uniform(-0.2, 0.2, 3)) * count / 3.0 + rng.uniform(0, count)})
    light = np.array([-0.45, -0.89])
    rgba = np.zeros((size, size, 4), np.float32)
    grain = cv2.GaussianBlur(rng.uniform(-1, 1, (size, size)).astype(np.float32), (0, 0), 1.2)
    for k, start in enumerate(splits):
        end = splits[(k + 1) % len(splits)]
        indices = [(start + j) % count for j in range(((end - start) % count or count) + 1)]
        face = [apex] + [corners[i] for i in indices]
        centroid = np.mean(face, axis=0) - apex
        normal = centroid / (np.linalg.norm(centroid) + 1e-6)
        shade = 0.22 + 0.55 * max(0.0, float(np.dot(normal, light))) + rng.uniform(-0.04, 0.04)
        facet = np.zeros((size, size), np.float32)
        cv2.fillPoly(facet, [np.round(np.array(face) * 16).astype(np.int32)], 1.0, cv2.LINE_AA, shift=4)
        tone = shade * (1.0 + 0.12 * grain)
        rgba[..., :3] = rgba[..., :3] * (1 - facet[..., None]) + tone[..., None] * facet[..., None]
        rgba[..., 3] = np.maximum(rgba[..., 3], facet)
    outline = np.zeros((size, size), np.float32)
    poly = np.round(np.array(corners) * 16).astype(np.int32)
    cv2.polylines(outline, [poly], True, 1.0, 4, cv2.LINE_AA, shift=4)
    for index in splits:
        cv2.line(outline, tuple(int(v) for v in apex), tuple(int(v) for v in corners[index]), 0.5, 2, cv2.LINE_AA)
    dark = 0.05
    rgba[..., :3] = rgba[..., :3] * (1 - outline[..., None]) + dark * outline[..., None]
    rgba[..., 3] = np.maximum(rgba[..., 3], np.clip(outline, 0.0, 1.0) * 0.95)
    image = (np.clip(rgba, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(image, 'RGBA').resize((64, 64), LANCZOS)


def sheet(cells, columns, cell):
    rows = (len(cells) + columns - 1) // columns
    out = Image.new('RGBA', (columns * cell, rows * cell), (0, 0, 0, 0))
    for k, image in enumerate(cells):
        out.paste(image, ((k % columns) * cell, (k // columns) * cell))
    return out


def main():
    out_dir = Path(sys.argv[sys.argv.index('--out') + 1]) if '--out' in sys.argv else OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    built = {}
    for name, palette in PALETTES.items():
        cells = [burst(v, 0, palette) for v in range(4)] + [burst(v, 1, palette) for v in range(4)]
        built['shock-%s' % name] = sheet(cells, 4, CELL)
    built['rocks'] = sheet([rock(n) for n in range(16)], 4, 64)
    for name, image in built.items():
        path = out_dir / (name + '.png')
        image.save(path, optimize=True)
        print(path, image.size)
    if '--preview' in sys.argv:
        target = Path(sys.argv[sys.argv.index('--preview') + 1])
        backdrop = Image.new('RGBA', (1024, 512 * 2 + 256), (34, 40, 66, 255))
        backdrop.alpha_composite(built['shock-cyan'], (0, 0))
        backdrop.alpha_composite(built['shock-azure'], (0, 512))
        backdrop.alpha_composite(built['rocks'].resize((512, 512), LANCZOS).crop((0, 0, 512, 256)), (0, 1024))
        backdrop.convert('RGB').save(target)
        print(target)


if __name__ == '__main__':
    main()
