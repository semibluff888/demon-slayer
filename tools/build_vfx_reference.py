"""Reference breakdown for character VFX: frame extraction, contact sheets,
palettes and review boards from a locally downloaded gameplay video.

Bulk frames live in output/vfx-reference/frames/ (git-ignored); only small
boards and notes are meant to be kept.

  python tools/build_vfx_reference.py overview --video V --start 2 --end 154
  python tools/build_vfx_reference.py burst --video V --start 12.5 --end 13.4 --name slash
  python tools/build_vfx_reference.py palette --name slash --colors 10
  python tools/build_vfx_reference.py board --name slash --frames 3,6,9,12 --out output/vfx-reference/tanjiro/boards/slash.jpg
"""
import argparse
import json
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FRAMES = ROOT / 'output/vfx-reference/frames'


def font(size):
    for name in ('consola.ttf', 'arial.ttf'):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def extract(video, start, end, fps, width, folder, quality=3):
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob('f_*.jpg'):
        old.unlink()
    subprocess.run(['ffmpeg', '-v', 'error', '-ss', str(start), '-to', str(end), '-i', str(video),
                    '-vf', f'fps={fps},scale={width}:-2', '-q:v', str(quality), str(folder / 'f_%04d.jpg')], check=True)
    (folder / 'meta.json').write_text(json.dumps({'video': str(video), 'start': start, 'end': end, 'fps': fps}), encoding='utf-8')
    return sorted(folder.glob('f_*.jpg'))


def sheet(paths, meta, out, columns, tile, first_index=0):
    rows = (len(paths) + columns - 1) // columns
    label_h = 18
    canvas = Image.new('RGB', (columns * tile[0], rows * (tile[1] + label_h)), (12, 14, 20))
    draw = ImageDraw.Draw(canvas)
    face = font(13)
    for i, path in enumerate(paths):
        index = first_index + i
        x, y = (i % columns) * tile[0], (i // columns) * (tile[1] + label_h)
        with Image.open(path) as image:
            canvas.paste(image.convert('RGB').resize(tile, Image.LANCZOS), (x, y + label_h))
        seconds = meta['start'] + index / meta['fps']
        draw.text((x + 4, y + 2), f'#{index + 1:04d}  {int(seconds // 60)}:{seconds % 60:05.2f}', fill=(230, 220, 190), font=face)
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, quality=88)


def contact_sheets(folder, columns, rows, tile):
    meta = json.loads((folder / 'meta.json').read_text(encoding='utf-8'))
    paths = sorted(folder.glob('f_*.jpg'))
    per = columns * rows
    outs = []
    for page in range(0, len(paths), per):
        out = folder / 'sheets' / f'sheet_{page // per + 1:02d}.jpg'
        sheet(paths[page:page + per], meta, out, columns, tile, page)
        outs.append(out)
    return outs


def palette(paths, colors, mask_dark=0.08):
    import cv2
    pixels = []
    for path in paths:
        with Image.open(path) as image:
            rgb = np.asarray(image.convert('RGB').resize((320, 180)), dtype=np.float32) / 255.0
        flat = rgb.reshape(-1, 3)
        pixels.append(flat[flat.max(axis=1) > mask_dark])
    data = np.concatenate(pixels).astype(np.float32)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 40, 1e-3)
    _, labels, centers = cv2.kmeans(data, colors, None, criteria, 4, cv2.KMEANS_PP_CENTERS)
    counts = np.bincount(labels.ravel(), minlength=colors)
    order = np.argsort(-counts)
    return [('#%02x%02x%02x' % tuple(int(c * 255) for c in centers[i]), round(float(counts[i]) / counts.sum(), 4)) for i in order]


def board(paths, out, width=1600, caption=''):
    images = [Image.open(p).convert('RGB') for p in paths]
    columns = min(4, len(images))
    tile_w = width // columns
    tile_h = int(tile_w * images[0].height / images[0].width)
    rows = (len(images) + columns - 1) // columns
    canvas = Image.new('RGB', (width, rows * tile_h + (28 if caption else 0)), (10, 12, 18))
    for i, image in enumerate(images):
        canvas.paste(image.resize((tile_w, tile_h), Image.LANCZOS), ((i % columns) * tile_w, (i // columns) * tile_h))
    if caption:
        ImageDraw.Draw(canvas).text((10, rows * tile_h + 6), caption, fill=(230, 220, 190), font=font(16))
    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out, quality=86)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    o = sub.add_parser('overview')
    o.add_argument('--video', required=True)
    o.add_argument('--start', type=float, required=True)
    o.add_argument('--end', type=float, required=True)
    o.add_argument('--fps', type=float, default=4)
    o.add_argument('--reuse', action='store_true', help='rebuild sheets from already extracted frames')
    b = sub.add_parser('burst')
    b.add_argument('--video', required=True)
    b.add_argument('--start', type=float, required=True)
    b.add_argument('--end', type=float, required=True)
    b.add_argument('--name', required=True)
    b.add_argument('--fps', type=float, default=30)
    b.add_argument('--width', type=int, default=1920)
    p = sub.add_parser('palette')
    p.add_argument('--name', required=True)
    p.add_argument('--frames', default='')
    p.add_argument('--colors', type=int, default=10)
    d = sub.add_parser('board')
    d.add_argument('--name', required=True)
    d.add_argument('--frames', required=True)
    d.add_argument('--out', required=True)
    d.add_argument('--caption', default='')
    args = parser.parse_args()
    if args.command == 'overview':
        folder = FRAMES / 'overview'
        if not args.reuse:
            extract(args.video, args.start, args.end, args.fps, 480, folder)
        else:
            (folder / 'meta.json').write_text(json.dumps({'video': args.video, 'start': args.start, 'end': args.end, 'fps': args.fps}), encoding='utf-8')
        for out in contact_sheets(folder, 6, 5, (320, 180)):
            print(out.relative_to(ROOT))
    elif args.command == 'burst':
        folder = FRAMES / args.name
        paths = extract(args.video, args.start, args.end, args.fps, args.width, folder, 2)
        for out in contact_sheets(folder, 4, 4, (480, 270)):
            print(out.relative_to(ROOT))
        print(len(paths), 'frames')
    elif args.command == 'palette':
        folder = FRAMES / args.name
        paths = sorted(folder.glob('f_*.jpg'))
        if args.frames:
            paths = [folder / f'f_{int(n):04d}.jpg' for n in args.frames.split(',')]
        for color, share in palette(paths, args.colors):
            print(color, share)
    elif args.command == 'board':
        folder = FRAMES / args.name
        paths = [folder / f'f_{int(n):04d}.jpg' for n in args.frames.split(',')]
        board(paths, ROOT / args.out, caption=args.caption)
        print(args.out)


if __name__ == '__main__':
    main()
