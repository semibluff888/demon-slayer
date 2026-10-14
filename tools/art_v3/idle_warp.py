"""Idle loop from one approved key drawing by moving-least-squares mesh warping.

The rig JSON lists control points on the key drawing (pixels) and periodic
motions. Points that no motion touches stay fixed (feet, ground contact).
Every frame is a deformation of the same drawing, so proportions, palette and
line weight never drift; motions are periodic, so the loop is seamless.

Rig format:
{
  "frames": 12, "fps": 10, "grid": 6, "alpha": 1.4,
  "points": {"foot_front": [x, y], "chest": [x, y], ...},
  "motions": [
    {"name": "breath", "points": {"chest": [0, -6], "shoulder": [0, -5]}, "phase": 0.0},
    {"name": "hem", "points": {"hem_back": [5, 0]}, "phase": -0.15}
  ]
}
Each motion displaces its points by amplitude * sin(2*pi*(t + phase)), t = i / frames.
Optional "offsets": {"foot_front": [dx, dy], ...} move points by a constant amount in
every frame (a pose correction of the key, e.g. both soles on one ground line).

Usage: python tools/art_v3/idle_warp.py --key KEY.png --rig RIG.json --out DIR [--preview GIF]
"""
import argparse
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def mls_rigid(grid, source, target, alpha=1.4, eps=1e-6):
    """Rigid MLS (Schaefer et al. 2006): maps each grid point through the
    deformation that carries `source` control points onto `target`."""
    v = grid[:, None, :]                                  # (N, 1, 2)
    p = source[None, :, :]                                # (1, K, 2)
    q = target[None, :, :]
    w = 1.0 / (np.sum((p - v) ** 2, axis=2) ** alpha + eps)  # (N, K)
    wsum = w.sum(axis=1, keepdims=True)
    p_star = (w[:, :, None] * p).sum(axis=1) / wsum      # (N, 2)
    q_star = (w[:, :, None] * q).sum(axis=1) / wsum
    p_hat = p - p_star[:, None, :]
    q_hat = q - q_star[:, None, :]
    d = grid - p_star                                     # (N, 2)
    # Rotation that best aligns p_hat to q_hat around each grid point.
    a = (w * (p_hat[:, :, 0] * q_hat[:, :, 0] + p_hat[:, :, 1] * q_hat[:, :, 1])).sum(axis=1)
    b = (w * (p_hat[:, :, 0] * q_hat[:, :, 1] - p_hat[:, :, 1] * q_hat[:, :, 0])).sum(axis=1)
    norm = np.sqrt(a * a + b * b) + eps
    cos, sin = a / norm, b / norm
    rotated = np.stack([cos * d[:, 0] - sin * d[:, 1], sin * d[:, 0] + cos * d[:, 1]], axis=1)
    return rotated + q_star


def displaced(rig, t):
    names = list(rig['points'])
    base = np.array([rig['points'][n] for n in names], dtype=np.float64)
    moved = base.copy()
    for name, offset in rig.get('offsets', {}).items():
        moved[names.index(name)] += np.array(offset, dtype=np.float64)
    for motion in rig['motions']:
        wave = math.sin(2 * math.pi * (t + motion.get('phase', 0.0)))
        for name, amplitude in motion['points'].items():
            moved[names.index(name)] += np.array(amplitude, dtype=np.float64) * wave
    return base, moved


def warp(image, rig, t):
    """Backward map: for each output pixel find where it came from in the key."""
    base, moved = displaced(rig, t)
    return warp_points(image, base, moved, int(rig.get('grid', 6)), float(rig.get('alpha', 1.4)))


def warp_points(image, base, moved, step=6, alpha=1.4):
    """Deform `image` so the control points at `base` land on `moved`."""
    height, width = image.shape[:2]
    xs = np.arange(0, width + step, step, dtype=np.float64)
    ys = np.arange(0, height + step, step, dtype=np.float64)
    gx, gy = np.meshgrid(xs, ys)
    grid = np.stack([gx.ravel(), gy.ravel()], axis=1)
    # Inverse mapping: deform output positions back onto the source drawing.
    source_positions = mls_rigid(grid, moved, base, alpha)
    map_x = source_positions[:, 0].reshape(gy.shape).astype(np.float32)
    map_y = source_positions[:, 1].reshape(gy.shape).astype(np.float32)
    map_x = cv2.resize(map_x, (len(xs) * step, len(ys) * step), interpolation=cv2.INTER_LINEAR)[:height, :width]
    map_y = cv2.resize(map_y, (len(xs) * step, len(ys) * step), interpolation=cv2.INTER_LINEAR)[:height, :width]
    # Premultiplied alpha avoids dark fringes when sampling between pixels.
    rgba = image.astype(np.float32) / 255.0
    rgba[:, :, :3] *= rgba[:, :, 3:4]
    # Bilinear sampling: cubic overshoot would ring along the ink lines.
    out = cv2.remap(rgba, map_x, map_y, interpolation=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
    alpha = np.clip(out[:, :, 3:4], 0.0, 1.0)
    out[:, :, :3] = np.where(alpha > 1e-4, out[:, :, :3] / np.maximum(alpha, 1e-4), 0)
    out[:, :, 3:4] = alpha
    return (np.clip(out, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def frames(key_path, rig):
    image = np.asarray(Image.open(key_path).convert('RGBA'))
    count = int(rig.get('frames', 12))
    return [warp(image, rig, i / count) for i in range(count)]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--key', required=True)
    parser.add_argument('--rig', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--preview')
    args = parser.parse_args()
    rig = json.loads(Path(args.rig).read_text(encoding='utf-8'))
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    images = [Image.fromarray(frame, 'RGBA') for frame in frames(args.key, rig)]
    for index, image in enumerate(images):
        image.save(out / ('idle-%02d.png' % index))
    if args.preview:
        backdrop = []
        for image in images:
            canvas = Image.new('RGBA', image.size, (27, 34, 51, 255))
            canvas.alpha_composite(image)
            backdrop.append(canvas.convert('RGB'))
        backdrop[0].save(args.preview, save_all=True, append_images=backdrop[1:], duration=int(1000 / rig.get('fps', 10)), loop=0)
    print('idle frames:', len(images), '->', out)


if __name__ == '__main__':
    main()
