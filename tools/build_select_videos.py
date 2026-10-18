"""Character-select showcase videos: magenta-keyed AI clips -> stacked-alpha Theora.

Godot only plays Theora, which has no alpha channel. Each output frame therefore stacks
premultiplied colour (top), a black gutter, and the matte as grey (bottom); the select
screen composites them in scripts/ui/shaders/stacked_alpha.gdshader.

  .venv\\Scripts\\python.exe -I tools/build_select_videos.py --import <clip.mp4> --id tanjiro
  .venv\\Scripts\\python.exe -I tools/build_select_videos.py [--only tanjiro]

Sources and provenance live in output/user-assets/select-videos/; runtime files are
art/characters/<id>/select.ogv, select.json and select-poster.png; review sheets go to
artifacts/select-videos/<id>/. See docs/select-videos.md.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'output/user-assets/select-videos'
MANIFEST = ASSETS / 'manifest.json'
REVIEW = ROOT / 'artifacts/select-videos'

FRAME = (576, 864)        # output colour/matte size (w, h); 1:1 at a 1080p window
GUTTER = 16               # black rows between colour and matte; keeps filtering apart
QUALITY = 8               # libtheora -q:v
GOP = 24                  # one keyframe per second; playback is sequential and loops from 0
FADE = 10                 # loop dissolve length in frames
HEAD = (0, 48)            # loop start search window (source frames)
TAIL_FROM = 192           # loop end search window starts here, ends at the last frame
LENGTH_WEIGHT = 0.3       # mild preference for longer loops, so clip endings are kept
SEED_KEY = 64.0           # magenta-ness below this is solid foreground (interiors are <= 52)
BG_TOLERANCE = 24.0       # per-channel distance to the fitted background plate
BG_KEY_MARGIN = 18.0      # pixels this close to the plate's magenta-ness are background
EDGE_RADIUS = 4.0         # transition pixels within this of a seed are unmixed against it
INTERIOR_KEY = 100.0      # enclosed pixels below this magenta-ness stay solid; above it they
                          # are background seen through haze (Nezuko's breath over her hair)
MIST_DEAD_ZONE = 14.0     # magenta-ness dead zone before isolated haze gets any alpha
SPILL_KEEP = 20.0         # residual magenta-ness allowed on opaque edge pixels


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)


def tool(name):
    path = shutil.which(name)
    if not path:
        sys.exit(f'{name} not found on PATH')
    return path


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rel(path):
    return Path(path).resolve().relative_to(ROOT).as_posix()


def read_manifest():
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text(encoding='utf-8'))
    return {'origin': 'user-supplied',
            'processing': 'per-frame magenta key with edge unmixing; premultiplied colour over '
                          'a grey matte, stacked in one Theora stream; audio removed',
            'records': []}


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def probe(path):
    out = run([tool('ffprobe'), '-v', 'error', '-select_streams', 'v:0', '-count_frames',
               '-show_entries', 'stream=codec_name,width,height,r_frame_rate,nb_read_frames',
               '-of', 'json', str(path)], capture_output=True, text=True).stdout
    stream = json.loads(out)['streams'][0]
    num, den = stream['r_frame_rate'].split('/')
    return {'codec': stream['codec_name'], 'width': int(stream['width']), 'height': int(stream['height']),
            'fps': float(num) / float(den), 'frames': int(stream['nb_read_frames'])}


def decode(path, width, height, matrix):
    """Yield uint8 RGB frames. Generated clips carry no colour tags, so the matrix is explicit."""
    cmd = [tool('ffmpeg'), '-v', 'error', '-i', str(path), '-map', '0:v:0', '-an',
           '-vf', f'scale=in_color_matrix={matrix}:in_range=tv,format=rgb24',
           '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1']
    size = width * height * 3
    with subprocess.Popen(cmd, stdout=subprocess.PIPE) as proc:
        while True:
            data = proc.stdout.read(size)
            if len(data) < size:
                break
            yield np.frombuffer(data, np.uint8).reshape(height, width, 3)
    if proc.returncode:
        sys.exit(f'ffmpeg failed decoding {path}')


# --- Keying ---------------------------------------------------------------------------

def magenta(rgb):
    return np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1]


def background_plate(c, key):
    """Smooth per-frame background: a quadratic surface fitted to clearly keyed pixels.
    The figure touches the frame edges, so a border median would be biased."""
    h, w = key.shape
    ys, xs = np.nonzero(key > 200)
    if len(ys) < 500:
        return None
    pick = np.linspace(0, len(ys) - 1, min(len(ys), 24000)).astype(int)
    ys, xs = ys[pick], xs[pick]
    u, v = xs / w - 0.5, ys / h - 0.5
    basis = np.stack([np.ones_like(u), u, v, u * u, u * v, v * v], axis=1)
    coef, *_ = np.linalg.lstsq(basis, c[ys, xs], rcond=None)
    gy, gx = np.mgrid[0:h, 0:w].astype(np.float32)
    gu, gv = gx / w - 0.5, gy / h - 0.5
    grid = np.stack([np.ones_like(gu), gu, gv, gu * gu, gu * gv, gv * gv], axis=-1)
    return np.clip(grid @ coef.astype(np.float32), 0, 255)


def key_frame(rgb, previous_plate=None):
    """Premultiplied float RGBA (0..1) plus the haze mask used for temporal smoothing."""
    c = rgb.astype(np.float32)
    k = magenta(c)
    plate = background_plate(c, k)
    if plate is None:
        plate = previous_plate
    kp = magenta(plate)
    seed = k < SEED_KEY
    bg = ~seed & ((np.abs(c - plate).max(axis=2) < BG_TOLERANCE) | (k > kp - BG_KEY_MARGIN))
    trans = ~seed & ~bg
    # Nearest solid-foreground colour for every pixel (index of the nearest seed).
    dist_seed, labels = cv2.distanceTransformWithLabels((~seed).astype(np.uint8), cv2.DIST_L2, 5,
                                                        labelType=cv2.DIST_LABEL_PIXEL)
    palette = np.zeros((int(labels.max()) + 1, 3), np.float32)
    palette[labels[seed]] = c[seed]
    nearest = palette[labels]
    dist_bg = cv2.distanceTransform((~bg).astype(np.uint8), cv2.DIST_L2, 5)
    alpha = seed.astype(np.float32)
    color = c.copy()
    # Antialiased edges and hair: unmix along background -> nearest foreground colour.
    edge = trans & (dist_seed <= EDGE_RADIUS)
    direction = nearest - plate
    along = np.sum((c - plate) * direction, axis=2) / np.maximum(np.sum(direction * direction, axis=2), 1.0)
    alpha[edge] = np.clip(along[edge], 0, 1)
    color[edge] = nearest[edge]
    # Pixels enclosed by the figure stay solid even if their hue drifts towards the key,
    # unless they are clearly key-coloured (gaps between hair strands behind breath haze).
    interior = edge & (dist_bg > 6) & (k < INTERIOR_KEY)
    alpha[interior] = 1.0
    color[interior] = c[interior]
    # Isolated translucent haze (breath mist): ratio key against the plate.
    haze = trans & ~edge
    ratio = np.clip((kp - k - MIST_DEAD_ZONE) / np.maximum(kp - MIST_DEAD_ZONE, 1.0), 0, 1)
    alpha[haze] = ratio[haze]
    a3 = np.maximum(alpha[..., None], 1e-3)
    unmixed = np.clip((c - plate * (1 - alpha[..., None])) / a3, 0, 255)
    color[haze] = unmixed[haze]
    # Light magenta despill on the outermost opaque ring.
    rim = seed & (dist_bg <= 2)
    excess = np.maximum(magenta(color) - SPILL_KEEP, 0) * rim
    color[..., 0] -= excess
    color[..., 2] -= excess
    alpha[alpha < 0.01] = 0
    rgba = np.dstack([np.clip(color, 0, 255) / 255.0 * alpha[..., None], alpha]).astype(np.float32)
    return rgba, haze, plate


def keyed_frames(path, info, matrix):
    """Key every frame at source resolution, smooth haze over 3 frames, then downscale."""
    plate = None
    window = []

    def finish(prev, cur, nxt):
        rgba, haze = cur
        if prev is not None and nxt is not None and haze.any():
            stack = np.stack([prev[0][..., 3], rgba[..., 3], nxt[0][..., 3]])
            smooth = np.median(stack, axis=0)
            scale = np.where(rgba[..., 3] > 1e-4, smooth / np.maximum(rgba[..., 3], 1e-4), 0)
            rgba = rgba.copy()
            rgba[haze, :3] *= scale[haze, None]
            rgba[haze, 3] = smooth[haze]
        small = cv2.resize(rgba, FRAME, interpolation=cv2.INTER_AREA)
        return np.clip(np.rint(small * 255), 0, 255).astype(np.uint8)

    for rgb in decode(path, info['width'], info['height'], matrix):
        rgba, haze, plate = key_frame(rgb, plate)
        window.append((rgba, haze))
        if len(window) == 2:
            yield finish(None, window[0], window[1])
        elif len(window) == 3:
            yield finish(window[0], window[1], window[2])
            window.pop(0)
    if len(window) >= 2:
        yield finish(window[-2], window[-1], None)


# --- Loop -----------------------------------------------------------------------------

def find_seam(frames):
    """Choose loop points (s, e) whose FADE-long overlap matches best in silhouette and colour,
    slightly favouring loops that keep more of the clip."""
    n = len(frames)
    tiny = [cv2.resize(f, (FRAME[0] // 8, FRAME[1] // 8), interpolation=cv2.INTER_AREA).astype(np.float32) / 255
            for f in frames]
    best = None
    for s in range(HEAD[0], HEAD[1] + 1):
        for e in range(max(TAIL_FROM, s + FADE * 3), n):
            score = 0.0
            for j in range(FADE):
                head, tail = tiny[s + j], tiny[e - FADE + 1 + j]
                ha, ta = head[..., 3] > 0.5, tail[..., 3] > 0.5
                iou = (ha & ta).sum() / max((ha | ta).sum(), 1)
                both = ha & ta
                colour = 1 - np.abs(head[..., :3] - tail[..., :3])[both].mean() if both.any() else 0
                score += iou + 0.5 * colour
            score = score / FADE + LENGTH_WEIGHT * (e - s) / n
            if best is None or score > best[0]:
                best = (score, s, e)
    return best


def over(top, bottom):
    return top + bottom * (1 - top[..., 3:4])


def loop_frames(frames, s, e):
    """Pure frames s+FADE..e-FADE, then the tail dissolving into the head: the head fades in
    over the tail, then the tail fades out underneath, so overlapping bodies never thin out."""
    out = [frames[i] for i in range(s + FADE, e - FADE + 1)]
    for j in range(FADE):
        t = j / (FADE - 1)
        head = frames[s + j].astype(np.float32) / 255 * min(1.0, 2 * t)
        tail = frames[e - FADE + 1 + j].astype(np.float32) / 255 * min(1.0, 2 * (1 - t))
        out.append(np.clip(np.rint(over(head, tail) * 255), 0, 255).astype(np.uint8))
    return out


# --- Encoding and checks --------------------------------------------------------------

def stacked(rgba):
    w, h = FRAME
    frame = np.zeros((h * 2 + GUTTER, w, 3), np.uint8)
    frame[:h] = rgba[..., :3]
    frame[h + GUTTER:] = rgba[..., 3:4]
    return frame


def encode(frames, fps, target):
    w, h = FRAME
    target.parent.mkdir(parents=True, exist_ok=True)
    pending = target.with_suffix('.pending.ogv')
    cmd = [tool('ffmpeg'), '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
           '-s', f'{w}x{h * 2 + GUTTER}', '-r', f'{fps:g}', '-i', 'pipe:0', '-an',
           '-vf', 'scale=out_color_matrix=bt601:out_range=tv,format=yuv420p',
           '-c:v', 'libtheora', '-q:v', str(QUALITY), '-g', str(GOP), '-map_metadata', '-1', str(pending)]
    with subprocess.Popen(cmd, stdin=subprocess.PIPE) as proc:
        for rgba in frames:
            proc.stdin.write(stacked(rgba).tobytes())
        proc.stdin.close()
    if proc.returncode:
        sys.exit(f'ffmpeg failed encoding {target}')
    pending.replace(target)


def decode_stacked(path):
    """Read an encoded clip back the way Godot does (BT.601 limited) -> uint8 RGBA frames."""
    w, h = FRAME
    frames = []
    for rgb in decode(path, w, h * 2 + GUTTER, 'bt601'):
        frames.append(np.dstack([rgb[:h], rgb[h + GUTTER:, :, 1]]))
    return frames


def verify(path, count, fps):
    info = probe(path)
    w, h = FRAME
    expected = {'codec': 'theora', 'width': w, 'height': h * 2 + GUTTER, 'frames': count}
    problems = [f'{k}={info[k]} (expected {v})' for k, v in expected.items() if info[k] != v]
    if abs(info['fps'] - fps) > 1e-6:
        problems.append(f'fps={info["fps"]}')
    streams = run([tool('ffprobe'), '-v', 'error', '-show_entries', 'stream=codec_type', '-of', 'csv=p=0',
                   str(path)], capture_output=True, text=True).stdout.split()
    if streams != ['video']:
        problems.append(f'streams={streams}')
    errors = run([tool('ffmpeg'), '-v', 'error', '-i', str(path), '-f', 'null', '-'],
                 capture_output=True, text=True).stderr.strip()
    if errors:
        problems.append('decode errors: ' + errors[:200])
    if problems:
        sys.exit(f'{rel(path)} failed verification: ' + '; '.join(problems))


def metrics(decoded, keyed):
    corners, residue, noise, error = [], [], [], []
    for got, want in zip(decoded, keyed):
        a = got[..., 3].astype(np.float32) / 255
        corners.append(max(a[:24, :24].max(), a[:24, -24:].max()))
        solid = a > 0.3
        straight = got[..., :3].astype(np.float32) / np.maximum(a[..., None], 1e-3)
        residue.append(float((magenta(straight)[solid] > 70).mean()) if solid.any() else 0.0)
        empty = want[..., 3] == 0
        noise.append(float(np.percentile(a[empty], 99)) if empty.any() else 0.0)
        error.append(float(np.abs(got.astype(np.float32) - want.astype(np.float32)).mean()))
    tiny = [cv2.resize(f, (FRAME[0] // 4, FRAME[1] // 4), interpolation=cv2.INTER_AREA).astype(np.float32)
            for f in decoded]
    # The clips are animated largely on twos, so compare the seam with real motion steps,
    # not with the (near-zero) held frames.
    steps = np.array([np.abs(tiny[i + 1] - tiny[i]).mean() for i in range(len(tiny) - 1)])
    moving = steps[steps > 0.5]
    seam = float(np.abs(tiny[0] - tiny[-1]).mean())
    return {'corner_alpha_max': round(float(max(corners)), 4),
            'magenta_residue_max': round(max(residue), 5),
            'background_alpha_p99_max': round(max(noise), 4),
            'codec_error_mean': round(float(np.mean(error)), 3),
            'seam_step': round(seam, 3),
            'motion_step_p90': round(float(np.percentile(moving, 90)) if len(moving) else 0.0, 3),
            'step_max': round(float(steps.max()), 3)}


def edges_touched(frames):
    alpha = np.max(np.stack([f[..., 3] for f in frames[::6]]), axis=0) > 128
    return {'left': bool(alpha[:, :2].any()), 'right': bool(alpha[:, -2:].any()),
            'top': bool(alpha[:2].any()), 'bottom': bool(alpha[-2:].any())}


# --- Review sheets --------------------------------------------------------------------

def composite(rgba, backdrop):
    a = rgba[..., 3:4].astype(np.float32) / 255
    return np.clip(rgba[..., :3].astype(np.float32) + backdrop * (1 - a), 0, 255).astype(np.uint8)


def backdrops():
    w, h = FRAME
    yy, xx = np.mgrid[0:h, 0:w]
    checker = np.where(((xx // 24) + (yy // 24)) % 2 == 0, 190, 120)[..., None].repeat(3, axis=2).astype(np.float32)
    ink = np.zeros((h, w, 3), np.float32) + np.array([20, 24, 36], np.float32)
    ink += (np.array([60, 30, 40], np.float32) * (yy / h)[..., None])
    return ink, checker


def review(decoded, folder):
    folder.mkdir(parents=True, exist_ok=True)
    ink, checker = backdrops()
    thumb = (FRAME[0] // 2, FRAME[1] // 2)
    picks = np.linspace(0, len(decoded) - 1, 8).astype(int)
    sheet = Image.new('RGB', (thumb[0] * 8, thumb[1] * 2))
    for i, index in enumerate(picks):
        for row, back in enumerate((ink, checker)):
            image = Image.fromarray(composite(decoded[index], back)).resize(thumb, Image.LANCZOS)
            sheet.paste(image, (i * thumb[0], row * thumb[1]))
    sheet.save(folder / 'sheet.png')
    seam = Image.new('RGB', (thumb[0] * 6, thumb[1]))
    for i, index in enumerate([len(decoded) - 3, len(decoded) - 2, len(decoded) - 1, 0, 1, 2]):
        seam.paste(Image.fromarray(composite(decoded[index], ink)).resize(thumb, Image.LANCZOS), (i * thumb[0], 0))
    ImageDraw.Draw(seam).line([(thumb[0] * 3, 0), (thumb[0] * 3, thumb[1])], fill=(255, 210, 120), width=2)
    seam.save(folder / 'seam.png')
    # Head and shoulders at 2x over ink: edge fringes show up here first.
    w, h = FRAME
    crops = Image.new('RGB', (w, h // 3))
    for i, index in enumerate(picks[::3][:3]):
        crop = composite(decoded[index], ink)[: h // 3, w // 4: w * 3 // 4]
        crops.paste(Image.fromarray(crop).resize((w // 3, h // 3), Image.LANCZOS), (i * (w // 3), 0))
    crops.save(folder / 'edges.png')
    print(f'  review: {rel(folder)}', flush=True)


# --- Commands -------------------------------------------------------------------------

def import_source(clip, key):
    clip = Path(clip)
    if not clip.is_file():
        sys.exit(f'missing {clip}')
    raw = ASSETS / 'raw' / f'{key}.mp4'
    raw.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(clip, raw)
    manifest = read_manifest()
    records = [r for r in manifest['records'] if r['key'] != key]
    info = probe(raw)
    records.append({'key': key, 'original_filename': clip.name, 'source': rel(raw),
                    'source_sha256': sha256(raw), 'source_size': [info['width'], info['height']],
                    'source_fps': info['fps'], 'source_frames': info['frames'], 'color_matrix': 'bt709'})
    manifest['records'] = sorted(records, key=lambda r: r['key'])
    save_json(MANIFEST, manifest)
    print(f'Imported {clip.name} as {rel(raw)}')


def build(record):
    key = record['key']
    source = ROOT / record['source']
    if sha256(source) != record['source_sha256']:
        sys.exit(f'{rel(source)} does not match its manifest hash')
    info = probe(source)
    print(f'{key}: keying {info["frames"]} frames at {info["width"]}x{info["height"]}', flush=True)
    frames = list(keyed_frames(source, info, record.get('color_matrix', 'bt709')))
    score, s, e = find_seam(frames)
    looped = loop_frames(frames, s, e)
    print(f'  loop source {s}..{e} (score {score:.3f}), {len(looped)} frames', flush=True)
    folder = ROOT / 'art/characters' / key
    video = folder / 'select.ogv'
    encode(looped, info['fps'], video)
    verify(video, len(looped), info['fps'])
    decoded = decode_stacked(video)
    poster = folder / 'select-poster.png'
    w, h = FRAME
    still = np.zeros((h * 2 + GUTTER, w, 3), np.uint8)
    still[:h] = decoded[0][..., :3]
    still[h + GUTTER:] = decoded[0][..., 3:4]
    Image.fromarray(still).save(poster, optimize=True)
    layout = {'version': 1, 'frame': [w, h], 'gutter': GUTTER, 'fps': info['fps'], 'frames': len(looped),
              'loop': {'source_start': s, 'source_end': e, 'fade': FADE, 'score': round(float(score), 4)},
              'edges': edges_touched(decoded)}
    save_json(folder / 'select.json', layout)
    measured = metrics(decoded, looped)
    review(decoded, REVIEW / key)
    save_json(REVIEW / key / 'metrics.json', measured)
    record.update({
        'params': {'frame': [w, h], 'gutter': GUTTER, 'theora_quality': QUALITY, 'gop': GOP, 'fade': FADE,
                   'seed_key': SEED_KEY, 'bg_tolerance': BG_TOLERANCE, 'bg_key_margin': BG_KEY_MARGIN,
                   'edge_radius': EDGE_RADIUS, 'interior_key': INTERIOR_KEY, 'mist_dead_zone': MIST_DEAD_ZONE, 'spill_keep': SPILL_KEEP,
                   'length_weight': LENGTH_WEIGHT},
        'loop': layout['loop'],
        'outputs': {name: {'path': rel(path), 'sha256': sha256(path), 'bytes': path.stat().st_size}
                    for name, path in (('video', video), ('poster', poster), ('layout', folder / 'select.json'))},
        'metrics': measured})
    print(f'  {rel(video)}: {video.stat().st_size / 1048576:.2f} MiB, {measured}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--import', dest='clip', help='register a source clip (requires --id)')
    parser.add_argument('--id', help='character id for --import')
    parser.add_argument('--only', action='append', help='rebuild only these ids')
    args = parser.parse_args()
    if args.clip:
        if not args.id:
            sys.exit('--import needs --id')
        import_source(args.clip, args.id)
        return
    manifest = read_manifest()
    records = [r for r in manifest['records'] if not args.only or r['key'] in args.only]
    if not records:
        sys.exit('nothing to build; register clips with --import')
    for record in records:
        build(record)
        save_json(MANIFEST, manifest)
    print('SELECT VIDEOS READY', flush=True)


if __name__ == '__main__':
    main()
