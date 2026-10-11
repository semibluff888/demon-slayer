"""Blade tracks for sword-attached VFX.

For every frame of a character atlas, finds the drawn katana and records the
hilt (hand side) and tip in the shared 1024x640 canvas. Runtime effects convert
these to fighter-local units exactly like FighterView draws the sprite.

Detection: steel-coloured, thin pixels (blade body, light edge, blue-violet
glints) -> Hough segments -> collinear merge -> the long line whose one end sits
at the hands (skin) is the held blade; the hand end is the hilt. Frames without
a held blade are null. Manual corrections live in tools/blade_overrides/<id>.json
and always win. QA sheets are written to artifacts/blade-qa/<id>/.

  python tools/build_blade_tracks.py tanjiro
"""
import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]


def load_frames(base):
    atlas = json.loads((base / 'atlas.json').read_text(encoding='utf-8'))
    width, height = atlas['canvas_size']
    pages = {}
    clips = {}
    for clip, info in atlas['clips'].items():
        frames = []
        for entry in info.get('frames', []):
            if entry['texture'] not in pages:
                pages[entry['texture']] = np.asarray(Image.open(base / entry['texture']).convert('RGBA'))
            x, y, w, h = entry['region']
            ox, oy = entry['offset']
            canvas = np.zeros((height, width, 4), np.uint8)
            canvas[oy:oy + h, ox:ox + w] = pages[entry['texture']][y:y + h, x:x + w]
            frames.append(canvas)
        clips[clip] = frames
    return atlas, clips


def masks(frame):
    rgb = frame[..., :3].astype(np.float32) / 255.0
    alpha = frame[..., 3] > 140
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    v = rgb.max(axis=2)
    s = (v - rgb.min(axis=2)) / np.maximum(v, 1e-4)
    steel = alpha & (((s < 0.22) & (v > 0.10)) | ((b > r + 0.04) & (b >= g) & (v < 0.85) & (s < 0.6)))
    skin = alpha & (r > 0.72) & (g > 0.52) & (b > 0.38) & (r > b + 0.12) & (s > 0.12) & (s < 0.55)
    # Light steel edge, or the blue-violet glint some swings are painted with.
    edge = alpha & (((v > 0.72) & (s < 0.12)) | ((b > r + 0.08) & (b > g + 0.04) & (s > 0.2) & (v > 0.35)))
    return alpha, steel.astype(np.uint8), skin.astype(np.uint8), edge.astype(np.uint8)


def thin(mask):
    blobs = cv2.morphologyEx(mask, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    blobs = cv2.dilate(blobs, np.ones((3, 3), np.uint8))
    return mask & (1 - blobs)


def segments(mask):
    found = cv2.HoughLinesP(mask * 255, 1, math.pi / 360, 28, minLineLength=38, maxLineGap=7)
    # OpenCV 4 returns (N, 1, 4) and OpenCV 5 returns (N, 4).
    return [] if found is None else [tuple(map(float, line)) for line in np.asarray(found).reshape(-1, 4)]


def merge(lines):
    """Groups collinear, touching segments; returns endpoint pairs of each group.
    A gap larger than a few pixels starts a new group, so the blade never fuses
    with a costume edge that merely shares its direction."""
    groups = []
    for x1, y1, x2, y2 in sorted(lines, key=lambda l: -math.hypot(l[2] - l[0], l[3] - l[1])):
        angle = math.atan2(y2 - y1, x2 - x1) % math.pi
        placed = False
        for group in groups:
            delta = abs(angle - group['angle'])
            delta = min(delta, math.pi - delta)
            dx, dy = math.cos(group['angle']), math.sin(group['angle'])
            nx, ny = -dy, dx
            offset = abs((x1 - group['x']) * nx + (y1 - group['y']) * ny) + abs((x2 - group['x']) * nx + (y2 - group['y']) * ny)
            t1 = (x1 - group['x']) * dx + (y1 - group['y']) * dy
            t2 = (x2 - group['x']) * dx + (y2 - group['y']) * dy
            gap = max(min(t1, t2) - group['tmax'], group['tmin'] - max(t1, t2), 0)
            if delta < 0.10 and offset < 12 and gap <= 10:
                group['points'] += [(x1, y1), (x2, y2)]
                group['tmin'] = min(group['tmin'], t1, t2)
                group['tmax'] = max(group['tmax'], t1, t2)
                placed = True
                break
        if not placed:
            t2 = (x2 - x1) * math.cos(angle) + (y2 - y1) * math.sin(angle)
            groups.append({'angle': angle, 'x': x1, 'y': y1, 'tmin': min(0.0, t2), 'tmax': max(0.0, t2), 'points': [(x1, y1), (x2, y2)]})
    result = []
    for group in groups:
        pts = np.array(group['points'])
        direction = np.array([math.cos(group['angle']), math.sin(group['angle'])])
        t = (pts - pts.mean(axis=0)) @ direction
        a = pts.mean(axis=0) + direction * t.min()
        b = pts.mean(axis=0) + direction * t.max()
        result.append((a, b))
    return result


def coverage(mask, a, b, radius=2):
    length = max(1, int(np.linalg.norm(b - a)))
    hits = 0
    for i in range(length + 1):
        x, y = (a + (b - a) * i / length).round().astype(int)
        y0, y1, x0, x1 = max(0, y - radius), y + radius + 1, max(0, x - radius), x + radius + 1
        hits += 1 if mask[y0:y1, x0:x1].any() else 0
    return hits / (length + 1)


def detect(frame, feet_y):
    alpha, steel, skin, edge = masks(frame)
    lines = merge(segments(thin(steel)))
    if not lines or not skin.any():
        return None
    skin_points = np.argwhere(skin > 0)[:, ::-1].astype(np.float32)
    best = None
    for a, b in lines:
        length = float(np.linalg.norm(b - a))
        if length < 45:
            continue
        axis = (b - a) / length
        rel = skin_points - a
        t = np.clip(rel @ axis, 0, length)
        distance = np.linalg.norm(rel - np.outer(t, axis), axis=1)
        near = skin_points[distance < 14]
        if len(near) < 6:
            continue  # Not held: scabbard, sash or costume line.
        grip = a + axis * float(np.clip((near.mean(axis=0) - a) @ axis, 0, length))
        tip = a if np.linalg.norm(a - grip) > np.linalg.norm(b - grip) else b
        reach = float(np.linalg.norm(tip - grip))
        if reach < 60 or grip[1] > feet_y - 30:
            continue
        steel_cover = coverage(steel, grip, tip)
        edge_cover = coverage(edge, grip, tip, 3)
        if edge_cover < 0.12:
            continue  # A held blade always shows its light edge somewhere.
        score = reach * (0.4 + steel_cover) * (0.7 + edge_cover)
        if best is None or score > best['score']:
            best = {'hilt': [round(float(grip[0]), 1), round(float(grip[1]), 1)], 'tip': [round(float(tip[0]), 1), round(float(tip[1]), 1)],
                    'score': round(score, 1), 'steel': round(steel_cover, 2), 'edge': round(edge_cover, 2)}
    return best


def qa_sheet(clips, tracks, out, title):
    face = ImageFont.load_default()
    names = list(clips)
    tile = (320, 200)
    columns = 6
    entries = [(clip, i) for clip in names for i in range(len(clips[clip]))]
    for page in range(0, len(entries), 48):
        chunk = entries[page:page + 48]
        rows = (len(chunk) + columns - 1) // columns
        sheet = Image.new('RGB', (columns * tile[0], rows * tile[1]), (24, 26, 32))
        draw = ImageDraw.Draw(sheet)
        for k, (clip, i) in enumerate(chunk):
            frame = Image.fromarray(clips[clip][i])
            base = Image.new('RGBA', frame.size, (52, 56, 66, 255))
            base.alpha_composite(frame)
            canvas = ImageDraw.Draw(base)
            track = tracks[clip][i]
            if track:
                canvas.line([tuple(track['hilt']), tuple(track['tip'])], fill=(255, 220, 0, 255), width=3)
                hx, hy = track['hilt']
                tx, ty = track['tip']
                canvas.ellipse([hx - 7, hy - 7, hx + 7, hy + 7], outline=(0, 255, 90, 255), width=3)
                canvas.ellipse([tx - 7, ty - 7, tx + 7, ty + 7], outline=(255, 40, 60, 255), width=3)
            crop = base.crop((112, 80, 912, 580)).resize(tile, Image.LANCZOS)
            x, y = (k % columns) * tile[0], (k // columns) * tile[1]
            sheet.paste(crop.convert('RGB'), (x, y))
            label = f'{clip} {i}' + ('' if track else '  (none)') + (' *' if track and track.get('manual') else '')
            draw.text((x + 4, y + 3), label, fill=(255, 235, 160), font=face)
        out.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(out.with_name(f'{out.stem}_{page // 48 + 1:02d}.jpg'), quality=88)


def build(character):
    overrides_path = ROOT / 'tools/blade_overrides' / f'{character}.json'
    overrides = json.loads(overrides_path.read_text(encoding='utf-8')) if overrides_path.exists() else {}
    summary = {}
    for form, base in (('normal', ROOT / 'art/characters' / character), ('awakened', ROOT / 'art/characters' / character / 'awakening')):
        if not (base / 'atlas.json').exists():
            continue
        atlas, clips = load_frames(base)
        tracks = {}
        for clip, frames in clips.items():
            tracks[clip] = [detect(frame, atlas['feet_anchor'][1]) for frame in frames]
            for index, value in overrides.get(form, {}).get(clip, {}).items():
                if index.startswith('_'):
                    continue
                if int(index) < len(frames):
                    tracks[clip][int(index)] = None if value is None else dict(value, manual=True)
        data = {'canvas_size': atlas['canvas_size'], 'feet_anchor': atlas['feet_anchor'], 'clips': tracks,
                'note': 'hilt/tip in canvas pixels; null = no held blade. Generated by tools/build_blade_tracks.py.'}
        (base / 'blade-tracks.json').write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
        qa_sheet(clips, tracks, ROOT / 'artifacts/blade-qa' / character / f'{form}.jpg', form)
        found = sum(1 for clip in tracks.values() for t in clip if t)
        total = sum(len(clip) for clip in tracks.values())
        summary[form] = f'{found}/{total} frames with a held blade'
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == '__main__':
    build(sys.argv[1] if len(sys.argv) > 1 else 'tanjiro')
