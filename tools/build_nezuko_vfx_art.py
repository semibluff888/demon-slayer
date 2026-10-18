"""Builds Nezuko's procedural effect textures into art/effects/nezuko/ (deterministic).

The look follows the Hinokami Chronicles 爆血 (docs/vfx/nezuko-reference.md):
pink-magenta blood flame with a white-hot core and deep crimson, torn edges.
Two palettes: "pink" (her normal form) and "crimson" (鬼化, redder and darker).

  blaze-pink.png, blaze-crimson.png
      the contact burst: a full clump of curling flame tongues round a white-hot
      core, its rim frayed into soft blunt tongues with a few torn flakes outside.
      4 variants (columns) x 2 stages (rows): row 0 the dense first frame, row 1
      the same burst breaking up, which the game cross-fades into. 256 px cells.
  flame-strip.png
      flame strokes for ribbons: U runs along the stroke (0 = root, 1 = tip),
      V across it. White core line, pink body, magenta, a crimson edge eroded by
      noise, white streaks along the length and a tip that breaks into flecks.
      8 rows of 128 px (512 px long): 4 pink variants, then 4 crimson.
  claw-strip.png
      the 乱れ裂き claw stroke: thinner and sharper than the flame, a white core,
      hot pink body and crimson torn edges with chips peeling off one side.
      8 rows of 64 px (512 px long): 4 pink variants, then 4 crimson.
  flakes.png
      4 x 4 cells of torn blood flakes (irregular shards, crimson outline, hot
      pink inside, a pale highlight). 64 px cells.
  star.png
      2 cells of a white manga impact star with a soft black ink outline and
      speed lines inside. 256 px cells.

Rock chunks are shared with Akaza (art/effects/akaza/rocks.png).

  python tools/build_nezuko_vfx_art.py [--out DIR] [--preview out.png]

Rendered at twice the size and reduced with Lanczos. Import settings: mipmaps on
(see the .import files next to them).
"""
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'art/effects/nezuko'
LANCZOS = Image.Resampling.LANCZOS
CELL = 256
SS = 2

# Ramps measured on the reference frames: edge, deep, body, light, core.
PALETTES = {
    'pink': ['#3a0420', '#b0124e', '#f2309a', '#ffb4e4', '#ffffff'],
    # 鬼化 (爆血·猛撃): the same fire pushed toward blood red.
    'crimson': ['#300008', '#a80c26', '#ff2e5e', '#ffb0bc', '#ffffff'],
}


def rgb(hex_colour):
    return np.array([int(hex_colour[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


def ramp(palette, heat):
    """Colour by heat 0..1: deep -> body -> light -> white."""
    stops = [0.0, 0.3, 0.62, 0.9]
    colours = [rgb(c) for c in palette[1:]]
    out = np.zeros(heat.shape + (3,), np.float32)
    for i in range(len(stops) - 1):
        lo, hi = stops[i], stops[i + 1]
        u = np.clip((heat - lo) / (hi - lo), 0.0, 1.0)[..., None]
        band = (heat >= lo) & (heat < hi) if i < len(stops) - 2 else heat >= lo
        out = np.where(band[..., None], colours[i] * (1 - u) + colours[i + 1] * u, out)
    return out


def noise(rng, shape, blur):
    field = rng.uniform(-1.0, 1.0, shape).astype(np.float32)
    field = cv2.GaussianBlur(field, (0, 0), blur)
    return field / (np.abs(field).max() + 1e-6)


def tongue(mask, centre, angle, inner, length, width, bend):
    """One curling flame tongue: wide at the root, a blunt rounded tip, bent sideways."""
    steps = 16
    left, right = [], []
    for k in range(steps + 1):
        t = k / steps
        r = inner + (length - inner) * t
        a = angle + bend * t * t
        axis = np.array([np.cos(a), np.sin(a)])
        side = np.array([-axis[1], axis[0]])
        # Swells a little before narrowing into a rounded tip.
        w = width * (1.0 + 0.35 * np.sin(t * np.pi * 0.8)) * (1.0 - t) ** 0.7
        p = centre + axis * r
        left.append(p + side * w)
        right.append(p - side * w)
    poly = np.array(left + right[::-1], np.float32)
    cv2.fillPoly(mask, [np.round(poly * 16).astype(np.int32)], 1.0, cv2.LINE_AA, shift=4)


def shard(mask, centre, angle, length, width, rng):
    """A torn flake: an irregular sliver along `angle`."""
    axis = np.array([np.cos(angle), np.sin(angle)])
    side = np.array([-axis[1], axis[0]])
    count = int(rng.integers(5, 8))
    points = []
    for k in range(count):
        t = k / count * 2 * np.pi
        r = np.array([np.cos(t) * length, np.sin(t) * width]) * rng.uniform(0.6, 1.0)
        points.append(centre + axis * r[0] + side * r[1])
    cv2.fillPoly(mask, [np.round(np.array(points) * 16).astype(np.int32)], 1.0, cv2.LINE_AA, shift=4)


def burst(seed, stage, palette):
    rng = np.random.default_rng(2000 + seed)
    size = CELL * SS
    centre = np.array([size / 2, size / 2], np.float32)
    reach = size * 0.44
    mask = np.zeros((size, size), np.float32)
    phase = rng.uniform(0, 2 * np.pi, 2)
    lobes = lambda a: 1.0 + 0.12 * np.sin(3 * a + phase[0]) + 0.07 * np.sin(5 * a + phase[1])
    count = 64
    angles = np.sort(rng.uniform(0, 2 * np.pi, count))
    for n in range(count):
        layer = np.zeros_like(mask)
        length = min(reach * (0.55 + 0.35 * rng.uniform() ** 1.3) * lobes(angles[n]), reach)
        width = reach * rng.uniform(0.07, 0.12)
        inner = reach * 0.06
        bend = rng.uniform(0.25, 0.6) * (1 if rng.uniform() < 0.5 else -1)
        if stage == 1:
            if rng.uniform() < 0.35:
                continue
            length *= rng.uniform(1.0, 1.12)
            width *= 0.7
            inner = reach * rng.uniform(0.08, 0.18)
        tongue(layer, centre, angles[n], inner, length, width, bend)
        mask = np.maximum(mask, layer * rng.uniform(0.8, 1.0))
    body = np.zeros_like(mask)
    points = []
    for k in range(36):
        a = 2 * np.pi * k / 36
        points.append(centre + np.array([np.cos(a), np.sin(a)]) * reach * (0.5 if stage == 0 else 0.3) * lobes(a) * rng.uniform(0.9, 1.1))
    cv2.fillPoly(body, [np.round(np.array(points) * 16).astype(np.int32)], 1.0, cv2.LINE_AA, shift=4)
    mask = np.maximum(mask, body)
    # Breaking up: holes eaten into the fire (applied to the final alpha, so they
    # thin it instead of drawing dark rims).
    holes = np.clip((noise(rng, mask.shape, 7.0) + 0.6) * 2.0, 0.25, 1.0) if stage == 1 else np.ones_like(mask)
    # Torn flakes flung past the rim.
    flakes = np.zeros_like(mask)
    for n in range(14 if stage == 0 else 22):
        a = rng.uniform(0, 2 * np.pi)
        r = reach * rng.uniform(0.85, 1.05 if stage == 0 else 1.15)
        r = min(r, size * 0.48)
        shard(flakes, centre + np.array([np.cos(a), np.sin(a)]) * r, a + rng.uniform(-0.6, 0.6), reach * rng.uniform(0.04, 0.08), reach * rng.uniform(0.015, 0.03), rng)
    # Fine white streaks along the tongues give the painted texture.
    streaks = np.zeros_like(mask)
    for n in range(60):
        a = rng.uniform(0, 2 * np.pi)
        r0 = reach * rng.uniform(0.05, 0.3)
        r1 = reach * rng.uniform(0.45, 0.85)
        bend = rng.uniform(-0.25, 0.25)
        pts = []
        for k in range(9):
            t = k / 8
            aa = a + bend * t
            pts.append(centre + np.array([np.cos(aa), np.sin(aa)]) * (r0 + (r1 - r0) * t))
        cv2.polylines(streaks, [np.round(np.array(pts) * 16).astype(np.int32)], False, rng.uniform(0.4, 1.0), int(rng.integers(1, 3)) * 16 // 16, cv2.LINE_AA, shift=4)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    dist = np.hypot(xx - centre[0], yy - centre[1]) / reach
    soft = cv2.GaussianBlur(mask, (0, 0), 7.0)
    core = np.clip(1.0 - dist / (0.2 if stage == 0 else 0.12), 0.0, 1.0) ** 0.8
    heat = np.clip(soft * 0.4 + core * 0.6 + streaks * mask * 0.35 - dist * 0.22, 0.0, 1.0)
    if stage == 1:
        heat *= 0.8
    colour = ramp(palette, heat)
    # Flakes: hot pink inside a crimson rim.
    flake_heat = np.clip(cv2.erode(flakes, np.ones((5, 5), np.uint8)) * 0.55 + 0.2, 0.0, 1.0)
    flake_colour = ramp(palette, flake_heat)
    alpha = np.clip(mask * 1.1, 0.0, 1.0) * np.clip(1.5 - dist, 0.3, 1.0)
    colour = colour * alpha[..., None] + flake_colour * (flakes * (1.0 - alpha))[..., None]
    alpha = alpha + flakes * (1.0 - alpha)
    colour = colour / np.maximum(alpha[..., None], 1e-4)
    # A dark crimson outline round the fire, only outside the fill.
    grown = cv2.dilate(np.maximum(mask, flakes), np.ones((5, 5), np.uint8))
    edge = cv2.GaussianBlur(np.clip(grown - np.maximum(mask, flakes), 0.0, 1.0), (0, 0), 1.6) * 0.6
    out_alpha = alpha + edge * (1.0 - alpha)
    out_rgb = (colour * alpha[..., None] + rgb(palette[0]) * (edge * (1.0 - alpha))[..., None]) / np.maximum(out_alpha[..., None], 1e-4)
    halo = cv2.GaussianBlur(mask, (0, 0), 16.0) * 0.28
    halo_alpha = halo * (1.0 - out_alpha)
    final_alpha = out_alpha + halo_alpha
    final_rgb = (out_rgb * out_alpha[..., None] + rgb(palette[2]) * halo_alpha[..., None]) / np.maximum(final_alpha[..., None], 1e-4)
    final_alpha = final_alpha * holes
    image = (np.clip(np.dstack([final_rgb, final_alpha]), 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(image, 'RGBA').resize((CELL, CELL), LANCZOS)


def strip(seed, length, height, palette, claw):
    """A stroke for ribbons: U along it (root to tip), V across it."""
    rng = np.random.default_rng(3000 + seed + (500 if claw else 0))
    w, h = length * SS, height * SS
    u = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :]
    v = np.linspace(-1.0, 1.0, h, dtype=np.float32)[:, None]
    # The edge wanders and is eaten by noise; a claw is sharper and tears on one side.
    wander = noise(rng, (1, w), 18.0 if claw else 10.0) * (0.06 if claw else 0.14)
    rough = noise(rng, (h, w), 3.0 if claw else 5.0)
    half = 0.78 + wander + rough * (0.08 if claw else 0.16)
    across = np.abs(v - wander * 0.6) / np.maximum(half, 0.05)
    body = np.clip((1.0 - across) * (6.0 if claw else 3.5), 0.0, 1.0)
    if claw:
        # Chips peeling off the lower edge at irregular intervals.
        chips = np.zeros((h, w), np.float32)
        x = 0
        while x < w:
            x += int(rng.integers(w // 22, w // 9))
            cw = int(rng.integers(w // 60, w // 25))
            cv2.ellipse(chips, (x, int(h * 0.82)), (cw, int(h * rng.uniform(0.12, 0.22))), rng.uniform(-30, 30), 0, 360, 1.0, -1, cv2.LINE_AA)
        body *= 1.0 - chips * (v > 0)
    # Tip: breaks into flecks over the last stretch; root fades in.
    breakup = np.clip((u - (0.72 if claw else 0.6)) / 0.28, 0.0, 1.0)
    flecks = noise(rng, (h, w), 2.5)
    body *= np.clip((flecks + 1.0 - 1.6 * breakup) * 3.0, 0.0, 1.0) * np.clip(u / 0.04, 0.0, 1.0)
    # Heat: white core line, then light, body, deep toward the edge.
    streaks = np.clip(noise(rng, (h, w // 8), 1.2), 0.0, 1.0)
    streaks = cv2.resize(streaks, (w, h), interpolation=cv2.INTER_LINEAR) ** 2
    # A narrow white core; most of the width is the hot pink body, deep toward the edge.
    inside = np.clip(1.0 - across, 0.0, 1.0)
    heat = inside ** (2.4 if claw else 2.0) * 0.98 + 0.12 * inside
    heat = np.clip(heat + streaks * 0.3 * inside, 0.0, 1.0) * (1.0 - 0.3 * breakup)
    # The tip's flecks stay hot pink rather than going dark.
    heat = np.maximum(heat, 0.42 * breakup)
    colour = ramp(palette, heat)
    # A deep crimson rim; none round the tip's flecks (they would read as soot).
    edge = np.clip(cv2.GaussianBlur(cv2.dilate(body, np.ones((5, 5), np.uint8)) - body, (0, 0), 1.2), 0.0, 1.0) * 0.6 * (1.0 - breakup)
    alpha = body + edge * (1.0 - body)
    out_rgb = (colour * body[..., None] + rgb(palette[1]) * 0.7 * (edge * (1.0 - body))[..., None]) / np.maximum(alpha[..., None], 1e-4)
    image = (np.clip(np.dstack([out_rgb, alpha]), 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(image, 'RGBA').resize((length, height), LANCZOS)


def flake(seed, palette):
    rng = np.random.default_rng(4000 + seed)
    size = 64 * SS
    mask = np.zeros((size, size), np.float32)
    centre = np.array([size / 2, size / 2], np.float32)
    shard(mask, centre, rng.uniform(0, np.pi), size * rng.uniform(0.3, 0.42), size * rng.uniform(0.1, 0.2), rng)
    inner = cv2.erode(mask, np.ones((7, 7), np.uint8))
    heat = np.clip(cv2.GaussianBlur(inner, (0, 0), 4.0) * 0.45 + 0.28, 0.0, 1.0)
    colour = ramp(palette, heat)
    edge = np.clip(mask - inner, 0.0, 1.0)
    colour = colour * (1.0 - edge[..., None]) + rgb(palette[1]) * 0.6 * edge[..., None]
    image = (np.clip(np.dstack([colour, mask]), 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(image, 'RGBA').resize((64, 64), LANCZOS)


def star(seed):
    rng = np.random.default_rng(6000 + seed)
    size = CELL * SS
    centre = np.array([size / 2, size / 2], np.float32)
    count = 14
    points = []
    for k in range(count * 2):
        a = (k + rng.uniform(-0.25, 0.25)) * np.pi / count
        r = size * (rng.uniform(0.3, 0.47) if k % 2 == 0 else rng.uniform(0.12, 0.18))
        points.append(centre + np.array([np.cos(a), np.sin(a)]) * r)
    mask = np.zeros((size, size), np.float32)
    cv2.fillPoly(mask, [np.round(np.array(points) * 16).astype(np.int32)], 1.0, cv2.LINE_AA, shift=4)
    outline = np.zeros_like(mask)
    cv2.polylines(outline, [np.round(np.array(points) * 16).astype(np.int32)], True, 1.0, 6, cv2.LINE_AA, shift=4)
    lines = np.zeros_like(mask)
    for n in range(10):
        a = rng.uniform(0, 2 * np.pi)
        p0 = centre + np.array([np.cos(a), np.sin(a)]) * size * 0.08
        p1 = centre + np.array([np.cos(a), np.sin(a)]) * size * rng.uniform(0.2, 0.3)
        cv2.line(lines, tuple(int(c) for c in p0), tuple(int(c) for c in p1), 1.0, 2, cv2.LINE_AA)
    shade = np.clip(1.0 - lines * mask * 0.35, 0.0, 1.0)
    rgb_out = np.dstack([shade * 0.99, shade * 0.97, shade * 1.0]) * (1.0 - outline[..., None]) + 0.06 * outline[..., None]
    alpha = np.clip(np.maximum(mask * 0.96, outline * 0.85), 0.0, 1.0)
    halo = cv2.GaussianBlur(mask, (0, 0), 12.0) * 0.35 * (1.0 - alpha)
    rgb_out = (rgb_out * alpha[..., None] + 1.0 * halo[..., None]) / np.maximum((alpha + halo)[..., None], 1e-4)
    image = (np.clip(np.dstack([rgb_out, alpha + halo]), 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return Image.fromarray(image, 'RGBA').resize((CELL, CELL), LANCZOS)


def sheet(cells, columns, cell_w, cell_h=None):
    cell_h = cell_h or cell_w
    rows = (len(cells) + columns - 1) // columns
    out = Image.new('RGBA', (columns * cell_w, rows * cell_h), (0, 0, 0, 0))
    for k, image in enumerate(cells):
        out.paste(image, ((k % columns) * cell_w, (k // columns) * cell_h))
    return out


def main():
    out_dir = Path(sys.argv[sys.argv.index('--out') + 1]) if '--out' in sys.argv else OUT
    out_dir.mkdir(parents=True, exist_ok=True)
    built = {}
    for name, palette in PALETTES.items():
        cells = [burst(v, 0, palette) for v in range(4)] + [burst(v, 1, palette) for v in range(4)]
        built['blaze-%s' % name] = sheet(cells, 4, CELL)
    built['flame-strip'] = sheet([strip(v, 512, 128, PALETTES[name], False) for name in ('pink', 'crimson') for v in range(4)], 1, 512, 128)
    built['claw-strip'] = sheet([strip(v, 512, 64, PALETTES[name], True) for name in ('pink', 'crimson') for v in range(4)], 1, 512, 64)
    built['flakes'] = sheet([flake(n, PALETTES['pink']) for n in range(16)], 4, 64)
    built['star'] = sheet([star(n) for n in range(2)], 2, CELL)
    for name, image in built.items():
        path = out_dir / (name + '.png')
        image.save(path, optimize=True)
        print(path, image.size)
    if '--preview' in sys.argv:
        target = Path(sys.argv[sys.argv.index('--preview') + 1])
        backdrop = Image.new('RGBA', (1024, 512 * 2 + 1024 + 256), (52, 70, 46, 255))
        backdrop.alpha_composite(built['blaze-pink'], (0, 0))
        backdrop.alpha_composite(built['blaze-crimson'], (0, 512))
        backdrop.alpha_composite(built['flame-strip'], (0, 1024))
        backdrop.alpha_composite(built['claw-strip'], (512, 1024))
        backdrop.alpha_composite(built['flakes'], (512, 1536))
        backdrop.alpha_composite(built['star'], (0, 2048))
        backdrop.convert('RGB').save(target)
        print(target)


if __name__ == '__main__':
    main()
