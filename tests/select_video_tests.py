"""Character-select showcase clips: provenance, Theora stream shape and matte quality.

Header, manifest and poster checks need only Python; the full decode needs ffmpeg."""
import hashlib
import importlib.util
import json
import shutil
import struct
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_select_videos', ROOT / 'tools/build_select_videos.py')
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)
MANIFEST = json.loads(pipeline.MANIFEST.read_text(encoding='utf-8'))
ROSTER = ['akaza', 'nezuko', 'tanjiro', 'zenitsu']
W, H = pipeline.FRAME
GUTTER = pipeline.GUTTER


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ogg_streams(path):
    """First packet of every logical stream (beginning-of-stream pages)."""
    data = Path(path).read_bytes()
    starts, offset = [], 0
    while offset < len(data):
        if data[offset:offset + 4] != b'OggS':
            raise AssertionError(f'{path}: lost Ogg sync at {offset}')
        header_type = data[offset + 5]
        count = data[offset + 26]
        table = data[offset + 27:offset + 27 + count]
        body = offset + 27 + count
        if header_type & 0x02:
            starts.append(data[body:body + table[0]])
        offset = body + sum(table)
    return starts


def theora_info(packet):
    assert packet[:7] == b'\x80theora', 'not a Theora identification header'
    width = int.from_bytes(packet[14:17], 'big')
    height = int.from_bytes(packet[17:20], 'big')
    fps_num, fps_den = struct.unpack('>II', packet[22:30])
    pixel_format = (packet[41] >> 3) & 0x3
    return width, height, fps_num / fps_den, pixel_format


def unstack(rgb):
    return np.dstack([rgb[:H], rgb[H + GUTTER:, :, 1]])


def residue(rgba):
    alpha = rgba[..., 3].astype(np.float32) / 255
    solid = alpha > 0.3
    straight = rgba[..., :3].astype(np.float32) / np.maximum(alpha[..., None], 1e-3)
    return float((pipeline.magenta(straight)[solid] > 70).mean())


class SelectVideoTests(unittest.TestCase):
    def records(self):
        records = {r['key']: r for r in MANIFEST['records']}
        self.assertEqual(sorted(records), ROSTER)
        return records

    def test_provenance_matches_sources_and_outputs(self):
        self.assertEqual(MANIFEST['origin'], 'user-supplied')
        for key, record in self.records().items():
            self.assertEqual(sha256(ROOT / record['source']), record['source_sha256'], key)
            self.assertTrue(record['original_filename'].endswith('.mp4'), key)
            for name, output in record['outputs'].items():
                self.assertEqual(sha256(ROOT / output['path']), output['sha256'], f'{key} {name} is stale')
            for path in ('select.ogv', 'select.json', 'select-poster.png'):
                self.assertTrue((ROOT / 'art/characters' / key / path).is_file(), f'{key} {path}')

    def test_stream_is_silent_stacked_theora(self):
        for key in ROSTER:
            streams = ogg_streams(ROOT / 'art/characters' / key / 'select.ogv')
            self.assertEqual(len(streams), 1, f'{key}: audio or extra streams present')
            width, height, fps, pixel_format = theora_info(streams[0])
            self.assertEqual((width, height), (W, H * 2 + GUTTER), key)
            self.assertAlmostEqual(fps, 24.0, places=6, msg=key)
            self.assertEqual(pixel_format, 0, f'{key}: expected 4:2:0')

    def test_layout_and_poster(self):
        for key, record in self.records().items():
            folder = ROOT / 'art/characters' / key
            layout = json.loads((folder / 'select.json').read_text(encoding='utf-8'))
            self.assertEqual(layout['frame'], [W, H], key)
            self.assertEqual(layout['gutter'], GUTTER, key)
            loop = layout['loop']
            self.assertEqual(layout['frames'], loop['source_end'] - loop['source_start'] - loop['fade'] + 1, key)
            self.assertGreaterEqual(layout['frames'], 24 * 5, f'{key}: loop shorter than five seconds')
            self.assertTrue(layout['edges']['bottom'], f'{key}: clip no longer framed to the bottom edge')
            poster = np.asarray(Image.open(folder / 'select-poster.png').convert('RGB'))
            self.assertEqual(poster.shape, (H * 2 + GUTTER, W, 3), key)
            self.assertLessEqual(int(poster[H + 2:H + GUTTER - 2].max()), 20, f'{key}: gutter not black')
            rgba = unstack(poster)
            alpha = rgba[..., 3]
            self.assertLessEqual(int(max(alpha[:24, :24].max(), alpha[:24, -24:].max())), 8, f'{key}: corners not clear')
            torso = alpha[int(H * 0.45):int(H * 0.6), int(W * 0.42):int(W * 0.58)]
            self.assertGreater(float(torso.mean()), 250, f'{key}: torso not solid')
            excess = rgba[..., :3].astype(np.int32) - alpha[..., None].astype(np.int32)
            self.assertLess(float((excess > 12).mean()), 0.001, f'{key}: colour not premultiplied')
            self.assertLess(residue(rgba), 0.002, f'{key}: magenta left on the figure')

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'ffmpeg/ffprobe required')
    def test_decoded_clip_matte_and_loop_seam(self):
        for key in ROSTER:
            folder = ROOT / 'art/characters' / key
            layout = json.loads((folder / 'select.json').read_text(encoding='utf-8'))
            frames = pipeline.decode_stacked(folder / 'select.ogv')
            self.assertEqual(len(frames), layout['frames'], key)
            corners = max(max(f[:24, :24, 3].max(), f[:24, -24:, 3].max()) for f in frames)
            self.assertLessEqual(int(corners), 8, f'{key}: corners flicker')
            self.assertLess(max(residue(f) for f in frames[::8]), 0.003, f'{key}: magenta residue')
            tiny = [f[::4, ::4].astype(np.float32) for f in frames]
            steps = np.array([np.abs(tiny[i + 1] - tiny[i]).mean() for i in range(len(tiny) - 1)])
            seam = np.abs(tiny[0] - tiny[-1]).mean()
            self.assertLessEqual(seam, np.percentile(steps[steps > 0.5], 95) * 1.2, f'{key}: loop seam jumps')


if __name__ == '__main__':
    unittest.main()
