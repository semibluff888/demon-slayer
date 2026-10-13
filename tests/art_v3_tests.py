"""Quality gate for the v3 character art (tools/art_v3): provenance, one scale per
generated sheet, colour lock, head size, the idle loop and the derived awakened atlas."""
import hashlib
import json
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
V3 = {'tanjiro': ROOT / 'output/imagegen/tanjiro-v3'}
LOCKED = ('haori_green', 'uniform', 'skin')


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
                        self.assertTrue(0.62 <= part['resample_vs_idle'] <= 1.1, '%s resampled %.3f' % (part['id'], part['resample_vs_idle']))
                        for name in LOCKED:
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

    def test_awakened_atlas_is_the_base_art_plus_the_mark(self):
        for cid, out in self.characters.items():
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

            for clip in ('idle', 'walk', 'water_slash'):
                for normal, awakened in zip(base['clips'][clip]['frames'], awake['clips'][clip]['frames']):
                    changed = np.any(drawing(folder, normal) != drawing(folder / 'awakening', awakened), axis=2)
                    self.assertLessEqual(int(changed.sum()), 200, '%s: only the forehead mark differs' % clip)


if __name__ == '__main__':
    unittest.main(verbosity=2)
