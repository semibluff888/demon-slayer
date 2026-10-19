"""Game BGM assets: provenance, library agreement and Godot import settings.

Checks need only Python; loudness is verified by tools/build_music.py when it builds."""
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_music', ROOT / 'tools/build_music.py')
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)
SOURCES = json.loads((pipeline.SOURCES / 'sources.json').read_text(encoding='utf-8'))
LIBRARY = json.loads(pipeline.LIBRARY.read_text(encoding='utf-8'))
REPORT = json.loads((pipeline.SOURCES / 'build-report.json').read_text(encoding='utf-8'))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class MusicPipelineTests(unittest.TestCase):
    def test_sources_and_library_agree(self):
        source_ids = [track['id'] for track in SOURCES['tracks']]
        self.assertEqual(sorted(source_ids), sorted(LIBRARY['tracks']))
        self.assertEqual(len(source_ids), len(set(source_ids)))

    def test_source_files_match_their_checksums(self):
        for track in SOURCES['tracks']:
            path = pipeline.SOURCES / track['file']
            self.assertTrue(path.is_file(), path)
            self.assertEqual(sha256(path), track['sha256'], track['id'])
            self.assertTrue(track.get('source', '').startswith('https://'), track['id'])

    def test_only_used_sources_are_kept(self):
        kept = {path.stem for path in (pipeline.SOURCES / 'source').iterdir()}
        self.assertEqual(kept, set(LIBRARY['tracks']))

    def test_game_files_exist_and_import_without_engine_loops(self):
        for track_id, track in LIBRARY['tracks'].items():
            self.assertEqual(track['file'], f'res://art/music/{track_id}.ogg')
            asset = pipeline.ASSETS / f'{track_id}.ogg'
            self.assertTrue(asset.is_file(), asset)
            self.assertEqual(asset.read_bytes()[:4], b'OggS', asset)
            sidecar = asset.with_name(asset.name + '.import').read_text(encoding='utf-8')
            self.assertIn('importer="oggvorbisstr"', sidecar)
            # The director loops between cue points; an engine loop would bypass them.
            self.assertIn('loop=false', sidecar)

    def test_build_report_meets_the_loudness_target(self):
        reports = {entry['id']: entry for entry in REPORT['tracks']}
        self.assertEqual(set(reports), set(LIBRARY['tracks']))
        for track_id, entry in reports.items():
            self.assertLessEqual(abs(entry['output']['integrated'] - pipeline.TARGET_LUFS), pipeline.LOUDNESS_TOLERANCE, track_id)
            self.assertLessEqual(entry['output']['true_peak'], pipeline.TRUE_PEAK_CEILING, track_id)
            self.assertAlmostEqual(entry['duration'], LIBRARY['tracks'][track_id]['duration'], places=2)
            self.assertEqual(entry['bytes'], (pipeline.ASSETS / f'{track_id}.ogg').stat().st_size, track_id)

    def test_scene_choices_have_cues(self):
        specials = set(LIBRARY['choice_labels'])
        for scene, entry in LIBRARY['scenes'].items():
            self.assertIn(entry['default'], entry['choices'])
            for choice in entry['choices']:
                if choice in specials:
                    continue
                self.assertIn(scene, LIBRARY['tracks'][choice]['cues'], f'{choice} in {scene}')


if __name__ == '__main__':
    unittest.main()
