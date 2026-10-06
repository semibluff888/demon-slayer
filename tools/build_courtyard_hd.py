# coding: utf-8
"""Build the courtyard from a saved, reviewed Real-ESRGAN result; offline by default."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/courtyard-hd-v1'
RECORD = OUT / 'processing.json'
REVISION = 'courtyard-sr-v1'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.building')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(path)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ready():
    return RECORD.is_file() and (ROOT / read(RECORD)['output']).is_file()


def build(reprocess=False):
    if not ready():
        raise ValueError('Missing reviewed super-resolution record or source; existing stage stays intact.')
    record = read(RECORD)
    master = ROOT / record['source']
    processed = ROOT / record['output']
    if not record['accepted'] or sha256(master) != record['source_sha256']:
        raise ValueError('The master source or its approval differs from the recorded build.')
    if reprocess:
        # Explicit local inference. The default rebuild uses the preserved exact pixels.
        runtime = ROOT / 'output/super-resolution/runtime'
        distribution = read(ROOT / 'output/super-resolution/distribution.json')
        for dependency in distribution['files']:
            if sha256(ROOT / dependency['path']) != dependency['sha256']:
                raise ValueError('Offline inference dependency changed: ' + dependency['path'])
        candidate = OUT / 'raw/corps-courtyard-reprocessed.png'
        if candidate.exists():
            raise ValueError('Inspect existing reprocessed candidate before running inference again.')
        subprocess.run([
            str(runtime / 'realesrgan-ncnn-vulkan.exe'),
            '-i', str(master), '-o', str(candidate), '-m', str(runtime / 'models'),
            '-n', record['model'], '-s', '4', '-t', '256', '-j', '1:1:1',
        ], check=True)
        print('Wrote separate candidate for comparison:', candidate)
        return
    if sha256(processed) != record['sha256']:
        raise ValueError('Processed pixels differ from the reviewed source.')
    with Image.open(master) as original:
        original_size = list(original.size)
    with Image.open(processed) as image:
        if list(image.size) != record['actual_size'] or list(image.size) != [v * 4 for v in original_size]:
            raise ValueError('Unexpected source / neural output dimensions.')
        panorama = image.convert('RGB').crop(record['crop'])
    width, height = panorama.size
    if width != height * 4 or width % 4:
        raise ValueError('Expected a continuous 4:1 courtyard panorama.')
    target = ROOT / 'art/stages/corps_courtyard'
    target.mkdir(parents=True, exist_ok=True)
    panorama.save(target / 'panorama.png')
    gutter = 8
    padded = np.pad(np.array(panorama), ((gutter, gutter), (gutter, gutter), (0, 0)), mode='edge')
    tile_width = width // 4
    tiles = []
    for i in range(4):
        x = i * tile_width
        name = 'panorama-%d.png' % i
        Image.fromarray(padded[:, x:x + tile_width + 2 * gutter]).save(target / name)
        tiles.append(dict(texture=name, rect=[x, 0, tile_width, height],
                          region=[gutter, gutter, tile_width, height]))
    view_width = round(height * 1280 / 792)
    left = (width - view_width) // 2
    panorama.crop((left, 0, left + view_width, height)).resize(
        (960, 594), Image.Resampling.LANCZOS).save(target / 'thumbnail.jpg', quality=95)
    source = dict(path=record['output'], actual_size=record['actual_size'],
                  crop=record['crop'], sha256=record['sha256'],
                  method='neural-super-resolution', model=record['model'],
                  generated_master=record['source'], generated_size=original_size,
                  generated_sha256=record['source_sha256'])
    meta = dict(revision=REVISION, size=[width, height], render_size=[3168, 792],
                world_width=960, layers=['panorama'], parallax=[1.0], tiles=tiles, sources=[source])
    save(target / 'stage.json', meta)
    save(OUT / 'imports/corps-courtyard.json', dict(
        method='Real-ESRGAN x4plus-anime; entire original panorama processed before cutting tiles.',
        source=source, output_size=[width, height], resampled_after_inference=False,
        gutter_pixels=gutter, tiles=tiles, processing_record='output/imagegen/courtyard-hd-v1/processing.json'))
    review = ROOT / 'artifacts/uppercut-polish'
    review.mkdir(parents=True, exist_ok=True)
    panorama.resize((2048, 512), Image.Resampling.LANCZOS).save(review / 'courtyard-hd-overview.jpg', quality=96)
    print('Built %dx%d courtyard from neural super-resolution; generated master %dx%d.' %
          (width, height, original_size[0], original_size[1]))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--reprocess', action='store_true', help='Run saved local model into a separate candidate.')
    build(parser.parse_args().reprocess)
