"""Review sheets for tools/capture_tanjiro_vfx.gd captures.

  python tools/build_tanjiro_vfx_review.py sheet 236A-normal-right --ticks 8,10,12 [--crop x,y,w,h] [--columns 4]
  python tools/build_tanjiro_vfx_review.py compare 236A-normal-right --ticks 10,12 --reference strike_tide:5,6
  python tools/build_tanjiro_vfx_review.py video 236A-normal-right

Sheets go to artifacts/tanjiro-vfx/review/. The default crop follows the
action: the bounding box of pixels that differ from the first capture.
"""
import argparse
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / 'artifacts/tanjiro-vfx'
REVIEW = CAPTURES / 'review'
REFERENCE = ROOT / 'output/vfx-reference/frames'


def font(size):
    for name in ('consola.ttf', 'arial.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def frames(name):
    return sorted((CAPTURES / name).glob('t*.png'))


def auto_crop(paths, margin=40, aspect=16 / 9):
    base = np.asarray(Image.open(paths[0]).convert('RGB'), dtype=np.int16)
    mask = np.zeros(base.shape[:2], bool)
    for path in paths[1:]:
        mask |= np.abs(np.asarray(Image.open(path).convert('RGB'), dtype=np.int16) - base).max(axis=2) > 28
    mask[:120] = False  # HUD bars
    mask[-110:] = False
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return (0, 0, base.shape[1], base.shape[0])
    x0, x1, y0, y1 = xs.min() - margin, xs.max() + margin, ys.min() - margin, ys.max() + margin
    w, h = x1 - x0, y1 - y0
    if w / h < aspect:
        grow = int(h * aspect - w)
        x0 -= grow // 2
        w += grow
    else:
        grow = int(w / aspect - h)
        y0 -= grow // 2
        h += grow
    x0 = int(np.clip(x0, 0, base.shape[1] - w))
    y0 = int(np.clip(y0, 0, base.shape[0] - h))
    return (x0, y0, int(w), int(h))


def sheet(name, ticks, crop, columns, tile_width=480, out=None):
    paths = {int(p.stem[1:]): p for p in frames(name)}
    chosen = [t for t in ticks if t in paths] if ticks else sorted(paths)
    crop = crop or auto_crop([paths[t] for t in sorted(paths)])
    x, y, w, h = crop
    tile = (tile_width, int(tile_width * h / w))
    rows = (len(chosen) + columns - 1) // columns
    canvas = Image.new('RGB', (columns * tile[0], rows * (tile[1] + 20)), (12, 14, 20))
    draw = ImageDraw.Draw(canvas)
    for i, t in enumerate(chosen):
        image = Image.open(paths[t]).convert('RGB').crop((x, y, x + w, y + h)).resize(tile, Image.LANCZOS)
        px, py = (i % columns) * tile[0], (i // columns) * (tile[1] + 20)
        canvas.paste(image, (px, py + 20))
        draw.text((px + 4, py + 2), f'{name}  tick {t}', fill=(255, 230, 150), font=font(13))
    REVIEW.mkdir(parents=True, exist_ok=True)
    out = out or REVIEW / f'{name}.jpg'
    canvas.save(out, quality=90)
    return out, crop


def compare(name, ticks, reference, crop, out=None):
    clip, numbers = reference.split(':')
    refs = [REFERENCE / clip / f'f_{int(n):04d}.jpg' for n in numbers.split(',')]
    paths = {int(p.stem[1:]): p for p in frames(name)}
    crop = crop or auto_crop([paths[t] for t in sorted(paths)])
    x, y, w, h = crop
    tile_w = 640
    tile_h = int(tile_w * 9 / 16)
    count = max(len(ticks), len(refs))
    canvas = Image.new('RGB', (2 * tile_w, count * (tile_h + 20)), (12, 14, 20))
    draw = ImageDraw.Draw(canvas)
    for i in range(count):
        py = i * (tile_h + 20)
        if i < len(refs):
            canvas.paste(Image.open(refs[i]).convert('RGB').resize((tile_w, tile_h), Image.LANCZOS), (0, py + 20))
            draw.text((4, py + 2), f'reference {clip} #{refs[i].stem[2:]}', fill=(150, 220, 255), font=font(13))
        if i < len(ticks) and ticks[i] in paths:
            image = Image.open(paths[ticks[i]]).convert('RGB').crop((x, y, x + w, y + h))
            image = image.resize((tile_w, int(tile_w * h / w)), Image.LANCZOS).crop((0, 0, tile_w, tile_h))
            canvas.paste(image, (tile_w, py + 20))
            draw.text((tile_w + 4, py + 2), f'game {name} tick {ticks[i]}', fill=(255, 230, 150), font=font(13))
    REVIEW.mkdir(parents=True, exist_ok=True)
    out = out or REVIEW / f'{name}-compare.jpg'
    canvas.save(out, quality=90)
    return out


def montage(names, labels, fps, out_name):
    """Concatenates captures into one labelled video (full frames, HUD included)."""
    staging = REVIEW / ('_montage_' + out_name)
    staging.mkdir(parents=True, exist_ok=True)
    for old in staging.glob('*.png'):
        old.unlink()
    index = 0
    for name, label in zip(names, labels):
        for path in frames(name):
            image = Image.open(path).convert('RGB')
            draw = ImageDraw.Draw(image)
            size = max(18, image.height // 36)
            face = font(size)
            width = draw.textlength(label, font=face)
            x, y = (image.width - width) / 2, image.height * 0.16
            draw.rectangle([x - 12, y - 6, x + width + 12, y + size + 8], fill=(8, 10, 16))
            draw.text((x, y), label, fill=(255, 232, 160), font=face)
            image.save(staging / f'f{index:05d}.png')
            index += 1
    out = REVIEW / out_name
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', str(fps), '-i', str(staging / 'f%05d.png'),
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16', '-r', '60', str(out)], check=True)
    for old in staging.glob('*.png'):
        old.unlink()
    staging.rmdir()
    return out


def video(name, fps=60):
    REVIEW.mkdir(parents=True, exist_ok=True)
    out = REVIEW / f'{name}.mp4'
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-framerate', str(fps), '-pattern_type', 'glob', '-i', str(CAPTURES / name / 't*.png'),
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16', str(out)], check=True)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['sheet', 'compare', 'video', 'montage'])
    parser.add_argument('name', help='capture folder; for montage, comma-separated folders')
    parser.add_argument('--labels', default='', help='montage: "|"-separated captions')
    parser.add_argument('--fps', type=int, default=60, help='montage: playback rate (60 = real time)')
    parser.add_argument('--ticks', default='')
    parser.add_argument('--crop', default='')
    parser.add_argument('--columns', type=int, default=4)
    parser.add_argument('--reference', default='')
    parser.add_argument('--out', default='')
    args = parser.parse_args()
    ticks = [int(t) for t in args.ticks.split(',') if t]
    crop = tuple(int(v) for v in args.crop.split(',')) if args.crop else None
    out = (ROOT / args.out) if args.out else None
    if args.command == 'sheet':
        path, used = sheet(args.name, ticks, crop, args.columns, out=out)
        print(path.relative_to(ROOT), 'crop', used)
    elif args.command == 'compare':
        print(compare(args.name, ticks, args.reference, crop, out).relative_to(ROOT))
    elif args.command == 'montage':
        names = args.name.split(',')
        labels = args.labels.split('|') if args.labels else names
        print(montage(names, labels, args.fps, Path(args.out).name if args.out else 'montage.mp4').relative_to(ROOT))
    else:
        print(video(args.name).relative_to(ROOT))


if __name__ == '__main__':
    main()
