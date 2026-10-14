"""Quality gate for the v3 character art (tools/art_v3): provenance, one scale per
generated sheet, colour lock, head size, the idle loop and the derived awakened atlas.
Characters, locked materials and the awakening derivation come from tools/art_v3/spec."""
import hashlib
import json
import unittest
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SPECS = {path.stem: json.loads(path.read_text(encoding='utf-8')) for path in sorted((ROOT / 'tools/art_v3/spec').glob('*.json'))
         if not path.stem.endswith('-rig')}
V3 = {cid: ROOT / 'output/imagegen' / (cid + '-v3') for cid in SPECS}


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


class ArtV3Tests(unittest.TestCase):
    def setUp(self):
        self.characters = {cid: out for cid, out in V3.items()
                           if (out / 'pack.json').exists() and read(ROOT / 'art/characters' / cid / 'atlas.json').get('revision') == cid + '-v3'}
        if not self.characters:
            self.skipTest('No character ships v3 art yet')

    def test_outputs_match_the_recorded_pack(self):
        for cid, out in self.characters.items():
            for path, digest in read(out / 'pack.json')['outputs'].items():
                with self.subTest(path=path):
                    self.assertEqual(sha(ROOT / path), digest)

    def test_every_clip_has_registered_sources(self):
        for cid, out in self.characters.items():
            pack = read(out / 'pack.json')
            for clip, count in {**pack['clips'], **pack['round_clips'], **pack['awakened_clips']}.items():
                with self.subTest(clip=clip):
                    record = read(out / 'imports' / (clip + '.json'))
                    self.assertEqual(len(record['frames']), count)
                    for part in record.get('parts', []):
                        self.assertEqual(sha(ROOT / part['source']), part['sha256'], part['id'])
                        # Every sheet stays near the approved line weight; upright sheets come out larger (0.66).
                        # A body lying or flying flat does not fit its column at full size, so
                        # the model draws it smaller and it is enlarged a little more.
                        modes = {f.get('anchor_mode') for f in record['frames'] if f.get('part') == part['id']}
                        limit = 1.2 if modes and modes <= {'lying', 'pelvis'} else 1.1
                        self.assertTrue(0.62 <= part['resample_vs_idle'] <= limit, '%s resampled %.3f' % (part['id'], part['resample_vs_idle']))
                        for name in SPECS[cid]['materials']['locked']:
                            if name in part['palette_delta_e_after']:
                                self.assertLessEqual(part['palette_delta_e_after'][name], 4.5, '%s %s colour drift' % (part['id'], name))
                    for frame in record['frames']:
                        self.assertFalse(frame.get('flags'), '%s frame %s: %s' % (clip, frame.get('frame'), frame.get('flags')))

    def test_idle_is_a_seamless_breathing_loop(self):
        for cid, out in self.characters.items():
            idle = read(ROOT / 'art/characters' / cid / 'atlas.json')['clips']['idle']
            self.assertTrue(idle['cycle'] and idle['loop'])
            self.assertEqual(len(idle['frames']), 12)
            frames = [np.asarray(Image.open(p).convert('RGBA')).astype(np.int16) for p in sorted((out / 'imports/idle').glob('frame-*.png'))]
            steps = [np.abs(frames[i] - frames[(i + 1) % len(frames)]).mean() for i in range(len(frames))]
            self.assertLessEqual(steps[-1], max(steps[:-1]) * 1.5, 'the last drawing must flow back into the first')
            bottoms = {Image.fromarray(f.astype(np.uint8)).getbbox()[3] for f in frames}
            self.assertEqual(len(bottoms), 1, 'feet stay planted through the loop')

    def test_awakened_atlas_is_derived_from_the_base_art(self):
        for cid, out in self.characters.items():
            derivation = SPECS[cid]['awakening']
            folder = ROOT / 'art/characters' / cid
            base = read(folder / 'atlas.json')
            awake = read(folder / 'awakening/atlas.json')
            for clip, info in base['clips'].items():
                with self.subTest(clip=clip):
                    self.assertIn(clip, awake['clips'])
                    self.assertEqual(len(awake['clips'][clip]['frames']), len(info['frames']))
                    for key in ('fps', 'loop', 'phase_breaks'):
                        self.assertEqual(awake['clips'][clip].get(key), info.get(key))
            pages = {}

            def drawing(directory, entry):
                path = directory / entry['texture']
                if path not in pages:
                    pages[path] = Image.open(path).convert('RGBA')
                x, y, w, h = entry['region']
                canvas = Image.new('RGBA', (1024, 640))
                canvas.alpha_composite(pages[path].crop((x, y, x + w, y + h)), tuple(entry['offset']))
                return np.asarray(canvas).astype(np.int16)

            for clip in SPECS[cid]['qa']['sample_clips']:
                for normal, awakened in zip(base['clips'][clip]['frames'], awake['clips'][clip]['frames']):
                    first, second = drawing(folder, normal), drawing(folder / 'awakening', awakened)
                    changed = np.any(first != second, axis=2)
                    if derivation['mode'] == 'mark':
                        self.assertLessEqual(int(changed.sum()), 200, '%s: only the forehead mark differs' % clip)
                        continue
                    # Godspeed grade: same alpha, colour changes only on the gold materials
                    # and along the silhouette edge.
                    self.assertTrue(np.array_equal(first[:, :, 3], second[:, :, 3]), '%s: the grade keeps the geometry' % clip)
                    self.assertTrue(changed.any(), '%s: the awakened form is graded' % clip)
                    self.assertFalse((changed & ~graded_area(first.astype(np.uint8), derivation)).any(), '%s: grade outside its materials' % clip)


def graded_area(rgba, derivation):
    """Pixels awaken.bake_grade may touch: the gold class (feathered) and the rim band."""
    rule = derivation['gold']
    hsv = cv2.cvtColor(np.ascontiguousarray(rgba[:, :, :3]), cv2.COLOR_RGB2HSV).astype(np.int16)

    def within(channel, bounds):
        low, high = bounds
        return (channel >= low) & (channel <= high) if low <= high else (channel >= low) | (channel <= high)

    gold = (rgba[:, :, 3] > 160) & within(hsv[:, :, 0], rule['h']) & within(hsv[:, :, 1], rule['s']) & within(hsv[:, :, 2], rule['v'])
    area = cv2.dilate(gold.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool)
    width = int(derivation.get('rim_px', 0))
    if width:
        solid = (rgba[:, :, 3] > 40).astype(np.uint8)
        area |= (solid > 0) & (cv2.erode(solid, np.ones((2 * width + 1, 2 * width + 1), np.uint8)) == 0)
    return area


if __name__ == '__main__':
    unittest.main(verbosity=2)
