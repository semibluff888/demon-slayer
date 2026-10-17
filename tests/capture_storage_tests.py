"""Behavioral safeguards for disposable capture storage and its cleanup policy."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('capture_output', ROOT / 'tools/capture_output.py')
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class CaptureStorageTests(unittest.TestCase):
    def setUp(self):
        (ROOT / 'artifacts').mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='storage-test-', dir=ROOT / 'artifacts')
        self.folder = Path(self.temp.name) / 'sequence'
        self.addCleanup(self.temp.cleanup)

    def frames(self, indices):
        self.folder.mkdir(parents=True, exist_ok=True)
        for index in indices:
            Image.new('RGB', (32, 24), (index * 20 % 256, 50, 100)).save(self.folder / f't{index:03d}.png')

    def test_runtime_and_traversal_are_rejected(self):
        for path in [ROOT / 'art', ROOT / 'artifacts', ROOT / 'artifacts/../art', ROOT / 'output/imagegen']:
            with self.assertRaises(ValueError):
                storage.local(path)

    def test_tracked_frames_are_never_reset(self):
        self.frames([0])
        frame = self.folder / 't000.png'
        with patch.object(storage, 'tracked_files', return_value={os.path.normcase(str(frame))}):
            with self.assertRaises(ValueError):
                storage.prepare(self.folder, os.getpid(), 60, keep_frames=True)
        self.assertTrue(frame.is_file())

    def test_active_capture_cannot_be_replaced(self):
        storage.prepare(self.folder, os.getpid(), 60, keep_frames=True)
        self.frames([0])
        with self.assertRaisesRegex(RuntimeError, 'already active'):
            storage.prepare(self.folder, os.getpid(), 60, keep_frames=True)
        self.assertTrue((self.folder / 't000.png').is_file())

    def test_unreadable_or_recycled_markers_are_stale(self):
        self.folder.mkdir(parents=True)
        marker = self.folder / storage.MARKER
        owner = {'pid': os.getpid(), 'started': storage.process_started(os.getpid())}
        # A truncated write, a non-object, and a live PID whose start time
        # belongs to another process.
        for text in ['{"pid": 12', json.dumps([os.getpid()]), json.dumps({'pid': os.getpid(), 'started': 1})]:
            marker.write_text(text)
            self.assertFalse(storage.owner_alive(storage.read_marker(self.folder)))
            storage.prepare(self.folder, os.getpid(), 60, keep_frames=True)
            self.assertEqual(storage.read_marker(self.folder), owner)
        self.assertFalse((self.folder / (storage.MARKER + '.tmp')).exists())

    def test_keep_frames_and_shorter_recapture(self):
        self.frames([0, 1, 2])
        (self.folder / 'notes.txt').write_text('keep this')
        (self.folder / 'capture.mp4').write_bytes(b'previous video')
        storage.prepare(self.folder, os.getpid(), 60, keep_frames=True)
        self.assertEqual(storage.frame_paths(self.folder), [])
        self.frames([0])
        storage.finish(self.folder)
        self.assertEqual(len(storage.frame_paths(self.folder)), 1)
        self.assertEqual((self.folder / 'notes.txt').read_text(), 'keep this')
        self.assertFalse((self.folder / 'capture.mp4').exists(), 'stale video beside new frames')
        self.assertTrue(json.loads((self.folder / 'capture.json').read_text())['keep_frames'])
        self.assertFalse((self.folder / storage.MARKER).exists())

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'ffmpeg/ffprobe required')
    def test_chunks_preserve_frame_count_timing_and_last_success(self):
        storage.prepare(self.folder, os.getpid(), 30)
        self.frames([0, 2, 4])
        storage.encode(self.folder)
        self.assertFalse(storage.frame_paths(self.folder))
        self.frames([6, 8])
        storage.finish(self.folder)
        video = self.folder / 'capture.mp4'
        storage.verify(video, 5, shutil.which('ffprobe'))
        result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=r_frame_rate,duration',
                                 '-of', 'json', str(video)], check=True, capture_output=True, text=True)
        stream = json.loads(result.stdout)['streams'][0]
        self.assertEqual(stream['r_frame_rate'], '30/1')
        self.assertAlmostEqual(float(stream['duration']), 5 / 30, places=4)
        self.assertFalse(storage.frame_paths(self.folder))
        self.assertFalse((self.folder / storage.PARTS).exists())
        previous = video.read_bytes()
        storage.prepare(self.folder, os.getpid(), 30)
        self.frames([0, 2])
        with patch.object(storage, 'verify', side_effect=RuntimeError('verification failure')):
            with self.assertRaisesRegex(RuntimeError, 'verification failure'):
                storage.encode(self.folder)
        self.assertEqual(len(storage.frame_paths(self.folder)), 2)
        self.assertEqual(video.read_bytes(), previous)
        self.assertFalse((self.folder / storage.PARTS / 'pending.mp4').exists())

    def test_retention_dry_run_capacity_age_tracked_and_active(self):
        repo = Path(self.temp.name) / 'fixture'
        (repo / 'tools').mkdir(parents=True)
        shutil.copyfile(ROOT / 'tools/clean-local.ps1', repo / 'tools/clean-local.ps1')
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)

        def put(relative, data, days=0):
            file = repo / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(data)
            at = time.time() - days * 86400
            os.utime(file, (at, at))
            return file

        mib = b'x' * 1024 * 1024
        old = put('artifacts/old/frame-0000.png', mib, 2)
        # Two fresh captures exceed the budget together but sit in the grace window.
        new = put('artifacts/new/frame-0000.png', mib)
        fresh = put('artifacts/fresh/t000.png', mib, 0.5)
        expired = put('artifacts/expired/proof.mp4', b'x', 8)
        protected = put('artifacts/protected/source.txt', b'x', 20)
        ignore = put('artifacts/.gdignore', b'', 20)
        owner = {'pid': os.getpid(), 'started': storage.process_started(os.getpid())}
        active = put('artifacts/active/frame-0000.png', mib, 20)
        put(f'artifacts/active/{storage.MARKER}', json.dumps(owner).encode(), 20)
        # A truncated marker and a recycled PID must neither abort nor pin.
        broken = put(f'artifacts/broken/{storage.MARKER}', b'{"pid": 12', 20)
        recycled = put(f'artifacts/recycled/{storage.MARKER}', json.dumps(dict(owner, started=1)).encode(), 20)
        source = put('art/source.png', b'x', 20)
        subprocess.run(['git', '-C', str(repo), 'add', 'artifacts/protected/source.txt'], check=True)
        command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                   str(repo / 'tools/clean-local.ps1'), '-RetainRecent', '-MaxArtifactGiB', '0.001']
        subprocess.run(command, check=True, capture_output=True)
        self.assertTrue(old.exists())
        result = subprocess.run(command + ['-Apply'], check=True, capture_output=True, text=True, errors='replace')
        for removed in [old, expired, broken, recycled]:
            self.assertFalse(removed.exists(), removed)
        for kept in [new, fresh, protected, ignore, active, source]:
            self.assertTrue(kept.exists(), kept)
        self.assertIn('Artifact retention removed 4 files', result.stdout)
        self.assertIn('artifacts/old', result.stdout)
        self.assertIn('over the 0.001 GiB budget', result.stdout)


if __name__ == '__main__':
    unittest.main()
