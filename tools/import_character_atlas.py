"""Offline, explicit-crop animation importer. Never calls an image service.

Usage: .venv/Scripts/python tools/import_character_atlas.py spec.json
Spec paths are relative to spec.json; output must be inside art/characters/.
Every crop supplies its own *measured* foot anchor and uses one common scale.
This preserves cloth/sword extensions without per-frame bounding-box resizing.
See output/imagegen/atlas-spec.example.json.
"""
import argparse
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def chroma_key(image, matte, threshold=28, feather=48):
    """Remove only a specified solid key; preserve any existing alpha.

    Linear edge unmatting removes colored fringes. It cannot repair a generated
    hand, sword, face or foot anchor: those must pass manual art review first.
    """
    image = image.convert('RGBA')
    pixels = []
    for r, g, b, old_alpha in image.getdata():
        rgb = (r, g, b)
        distance = math.sqrt(sum((rgb[i] - matte[i]) ** 2 for i in range(3)))
        coverage = max(0.0, min(1.0, (distance - threshold) / feather))
        if coverage <= 0:
            pixels.append((0, 0, 0, 0))
            continue
        clean = tuple(max(0, min(255, round((rgb[i] - matte[i] * (1 - coverage)) / coverage))) for i in range(3))
        pixels.append(clean + (round(old_alpha * coverage),))
    image.putdata(pixels)
    return image


def normalize_frame(image, crop, foot, canvas_size, anchor, scale, matte=None):
    if len(crop) != 4 or crop[2] <= 0 or crop[3] <= 0:
        raise ValueError('Invalid crop rectangle')
    x, y, w, h = crop
    if min(x, y) < 0 or x + w > image.width or y + h > image.height:
        raise ValueError('Frame crop extends outside source image')
    frame = image.crop((x, y, x + w, y + h)).convert('RGBA')
    if matte is not None:
        frame = chroma_key(frame, matte)
    target_size = (round(w * scale), round(h * scale))
    frame = frame.resize(target_size, Image.Resampling.LANCZOS)
    position = (round(anchor[0] - foot[0] * scale), round(anchor[1] - foot[1] * scale))
    ink = frame.getbbox()
    if ink is None:
        raise ValueError('Empty frame after key removal')
    if position[0] + ink[0] < 0 or position[1] + ink[1] < 0 or position[0] + ink[2] > canvas_size[0] or position[1] + ink[3] > canvas_size[1]:
        raise ValueError('Visible artwork would be clipped; enlarge the shared canvas')
    canvas = Image.new('RGBA', canvas_size, (0, 0, 0, 0))
    canvas.alpha_composite(frame, position)
    return canvas


def run(spec_path):
    spec_path = Path(spec_path).resolve()
    spec = json.loads(spec_path.read_text(encoding='utf-8-sig'))
    character = spec['character']
    if character not in ('tanjiro', 'zenitsu'):
        raise ValueError('Unknown character')
    output = ROOT / 'art' / 'characters' / character
    size = tuple(spec.get('canvas_size', [768, 768]))
    anchor = spec.get('feet_anchor', [384, 704])
    scale = float(spec.get('scale', 1.0))
    if scale <= 0 or max(size) > 4096 or min(size) < 1:
        raise ValueError('Invalid scale or canvas')
    atlas = {'feet_anchor': anchor, 'source_height': spec.get('source_height', 600), 'clips': {}}
    staged = []
    for clip, info in spec['clips'].items():
        if not clip.replace('_', '').isalnum():
            raise ValueError('Invalid clip name')
        frames = []
        for index, entry in enumerate(info['frames']):
            with Image.open(spec_path.parent / entry['source']) as source:
                frame = normalize_frame(source, entry['crop'], entry['foot'], size, anchor, scale, spec.get('matte_rgb'))
            relative = 'frames/{}-{:02d}.png'.format(clip, index)
            staged.append((output / relative, frame))
            frames.append(relative)
        if not frames:
            raise ValueError('Empty clip: ' + clip)
        cuts = info.get('phase_breaks', [max(1, len(frames) // 3), max(1, len(frames) * 2 // 3)])
        if not 0 < cuts[0] <= cuts[1] <= len(frames):
            raise ValueError('Invalid phase breaks for ' + clip)
        atlas['clips'][clip] = {'frames': frames, 'loop': info.get('loop', False), 'fps': info.get('fps', 12), 'phase_breaks': cuts}
    # Validate the whole spec and images before mutating game assets.
    for path, frame in staged:
        path.parent.mkdir(parents=True, exist_ok=True)
        frame.save(path)
    output.mkdir(parents=True, exist_ok=True)
    (output / 'atlas.json').write_text(json.dumps(atlas, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Imported {} frames for {}'.format(len(staged), character))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('spec')
    run(parser.parse_args().spec)
