"""Cut processed frames' drawings out of their generated sheets at one common scale, as
base drawings for edits (pose edit "images"): each drawing is keyed, palette-locked and
separated exactly as process.py does it, then resized from its sheet's scale to `--scale`
(canvas px per drawing px), so drawings from different sheets show the same body size.
Writes <out>/<clip>-<frame>.png and <out>/record.json (sources, hashes, factors).

Usage: python tools/art_v3/drawings.py --character akaza --frames annihilation:4,step_punch:4 \
           --scale 0.4 --out output/imagegen/akaza-v3/references/annihilation-bases
"""
import argparse

import numpy as np
from PIL import Image, ImageOps

from common import ROOT, cutout, production, read, rel, save, sha256, spec
import palette
from process import canonical, separate

COLUMN = 768


def drawing_of(character, canon, clip, frame, poses, jobs):
    """The drawing of one processed frame as generated, and the scale its sheet used."""
    record = read(production(character) / 'imports' / (clip + '.json'))
    info = next(f for f in record['frames'] if f['frame'] == frame)
    if info.get('copy_of') is not None:
        raise SystemExit('%s:%d repeats %s; cut the original instead' % (clip, frame, info['copy_of']))
    part = next(p for p in record['parts'] if p['id'] == info['part'])
    job = jobs[info['part']]
    sheet = np.asarray(cutout(Image.open(ROOT / job['out']), spec(character)))
    locked, _ = palette.lock(sheet, canon['palette'], palette.stats(sheet))
    drawing = separate(Image.fromarray(locked, 'RGBA'), job['metadata']['count'])[job['metadata']['frame_indices'].index(frame)][1]
    if frame in poses.get(clip, {}).get('mirror_frames', []):
        drawing = ImageOps.mirror(drawing)
    return drawing, part['scale'], job


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', required=True)
    parser.add_argument('--frames', required=True, help='clip:frame,...')
    parser.add_argument('--scale', type=float, required=True)
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    canon = canonical(args.character)
    poses = read(ROOT / 'tools/art_v3/poses' / (args.character + '.json'))['clips']
    jobs = {j['id']: j for j in read(production(args.character) / 'jobs.json')}
    folder = ROOT / args.out
    folder.mkdir(parents=True, exist_ok=True)
    made = []
    for entry in args.frames.split(','):
        clip, frame = entry.split(':')
        drawing, scale, job = drawing_of(args.character, canon, clip, int(frame), poses, jobs)
        factor = scale / args.scale
        resized = drawing.resize((round(drawing.width * factor), round(drawing.height * factor)), Image.Resampling.LANCZOS)
        if resized.width > COLUMN - 16:
            raise SystemExit('%s is %d px wide at scale %.3f; a wide column holds %d (use a larger --scale)' % (entry, resized.width, args.scale, COLUMN - 16))
        path = folder / ('%s-%s.png' % (clip, frame))
        resized.save(path)
        made.append(dict(clip=clip, frame=int(frame), drawing=rel(path), source=job['out'], source_sha256=sha256(ROOT / job['out']),
                         sheet_scale=scale, resized_by=round(factor, 4), size=list(resized.size)))
        print(entry, drawing.size, '->', resized.size)
    save(folder / 'record.json', dict(character=args.character, scale=args.scale, drawings=made))


if __name__ == '__main__':
    main()
