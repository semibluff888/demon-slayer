"""Validate real delivered artwork, packing and provenance without service access."""
import hashlib
import json
import sys
from pathlib import Path
import unittest
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
CHECK_PREVIEWS = False
EXPECTED = {'idle':6, 'walk':8, 'walk_back':8, 'crouch':3, 'jump':6, 'guard':3,
            'guard_low':3, 'hit':4, 'knockdown':5, 'throw':6, 'victory':6,
            'stand_light':6, 'stand_heavy':6, 'crouch_light':6, 'crouch_heavy':6,
            'air_light':6, 'air_heavy':6, 'dash_forward':8, 'dash_back':8,
            'jump_forward':8, 'jump_back':8, 'throw_success':12, 'thrown':12}

EXPECTED.update({'body_'+s+'_'+w:(6 if w=='light' else 9) for s in ('stand','crouch','air') for w in ('light','heavy')})
EXPECTED.update({'roll_forward':12,'roll_back':12,'throw_forward':12,'thrown_forward':12,'throw_tech':6})

def clip_counts(character):
    result = dict(EXPECTED)
    result.update({'water_slash':9,'water_wheel':9} if character=='tanjiro' else {'iai':9,'thunder':9,'body_crouch_heavy':8})
    result.update({'water_vortex':12,'water_dragon':15,'sun_arc':12} if character=='tanjiro' else {'iai_return':12,'sixfold':18,'godspeed':15})
    return result

class ArtworkTests(unittest.TestCase):
    def test_all_clips_are_real_distinct_frames_and_fit_atlas(self):
        for character in ('tanjiro', 'zenitsu'):
            directory = ROOT / 'art/characters' / character
            atlas = json.loads((directory / 'atlas.json').read_text(encoding='utf-8'))
            expected = clip_counts(character)
            self.assertEqual(set(atlas['clips']), set(expected))
            self.assertEqual(sum(len(c['frames']) for c in atlas['clips'].values()), sum(expected.values()))
            pages = {}
            for clip, count in expected.items():
                info = atlas['clips'][clip]
                self.assertEqual(len(info['frames']), count)
                hashes = set()
                for frame in info['frames']:
                    path = directory / frame['texture']
                    if str(path) not in pages:
                        pages[str(path)] = Image.open(path).convert('RGBA')
                    page = pages[str(path)]
                    x,y,w,h = frame['region']
                    self.assertGreaterEqual(min(x,y), 2)
                    self.assertLessEqual(x+w+2, page.width)
                    self.assertLessEqual(y+h+2, page.height)
                    ox,oy = frame['offset']
                    self.assertGreaterEqual(min(ox,oy), 0)
                    self.assertLessEqual(ox+w, atlas['canvas_size'][0])
                    self.assertLessEqual(oy+h, atlas['canvas_size'][1])
                    image = page.crop((x,y,x+w,y+h))
                    self.assertIsNotNone(image.getbbox())
                    hashes.add(hashlib.sha256(image.tobytes()).hexdigest())
                self.assertEqual(len(hashes), count, character + '/' + clip + ' must not duplicate static poses')
            idle_height = max(f['region'][3] for f in atlas['clips']['idle']['frames'])
            sweep_height = max(f['region'][3] for f in atlas['clips']['crouch_heavy']['frames'])
            self.assertLess(sweep_height, idle_height * 0.82,
                            character + '/crouch_heavy must stay low through windup and recovery')
            for page in pages.values():
                r,g,b,a = page.split()
                residual = ImageChops.subtract(ImageChops.darker(r,b),g).point(lambda v:255 if v>135 else 0)
                opaque = a.point(lambda v:255 if v>200 else 0)
                self.assertIsNone(ImageChops.multiply(residual,opaque).getbbox(), 'Opaque chroma-key residue')
                page.close()

    def test_local_assets_and_provenance(self):
        for character in ('tanjiro','zenitsu'):
            path = ROOT / 'art/characters' / character
            with Image.open(path / 'portrait.png') as portrait:
                self.assertEqual(portrait.mode, 'RGBA')
                self.assertEqual(portrait.getchannel('A').getextrema(), (0,255))
            with Image.open(path / 'avatar.png') as avatar:
                self.assertEqual(avatar.size, (192,192))
            for clip in clip_counts(character):
                # Later targeted replacements are represented by their real imports.
                candidates = list((ROOT/'output/imagegen/anime-v2/imports').glob(character+'-'+clip+'*.json'))
                self.assertTrue(candidates, character+'/'+clip)
                for spec in candidates:
                    data = json.loads(spec.read_text(encoding='utf-8'))
                    scales = {f['scale'] for f in data['frames']}
                    self.assertEqual(len(scales),1,'A clip must use a single physical scale')
                    for frame in data['frames']:
                        self.assertTrue((ROOT/frame['source']).is_file())
        stage = json.loads((ROOT/'art/stages/wisteria/stage.json').read_text(encoding='utf-8'))
        self.assertEqual(stage['layers'], ['panorama'])
        self.assertEqual(stage['parallax'], [1.0])
        if stage.get('revision') == 'battle-v5':
            self.assertEqual(stage['size'], [9600,2400])
            self.assertEqual(len(stage['tiles']), 4)
            self.assertEqual(len(stage['sources']), 21)
            for source in stage['sources']:
                self.assertEqual(hashlib.sha256((ROOT/source['path']).read_bytes()).hexdigest(), source['sha256'])
                self.assertGreaterEqual(source['actual_size'][0], source['target_rect'][2])
                self.assertGreaterEqual(source['actual_size'][1], source['target_rect'][3])
            for tile in stage['tiles']:
                with Image.open(ROOT/'art/stages/wisteria'/tile['texture']) as image:
                    self.assertEqual(image.size, (2416,2416))
            for cid in ('tanjiro','zenitsu'):
                with Image.open(ROOT/'art/characters'/cid/'battle-portrait.png') as image:
                    self.assertEqual(image.size, (1024,1024))
                    self.assertEqual(image.mode, 'RGBA')
                    self.assertEqual(image.getchannel('A').getextrema(), (0,255))
            for name in ('water-slash','water-wheel','thunder','water-dragon','sun-flame-arc'):
                with Image.open(ROOT/'art/effects'/(name+'-body.png')) as image:
                    self.assertEqual(image.mode, 'RGBA')
                    self.assertEqual(image.getchannel('A').getextrema()[0], 0)
        else:
            self.assertEqual(hashlib.sha256((ROOT/stage['source']).read_bytes()).hexdigest(), stage['source_sha256'])
            with Image.open(ROOT/'art/stages/wisteria/panorama.png') as image:
                self.assertEqual(image.size, (4608,1152))
        for effect in ('water-slash','water-wheel','thunder','impact'):
            self.assertTrue((ROOT/'art/effects'/(effect+'.png')).is_file())

    def test_generated_previews(self):
        if not CHECK_PREVIEWS:
            self.skipTest('Local previews are not versioned; rebuild art and pass --with-previews to validate them.')
        for character in ('tanjiro','zenitsu'):
            for clip in clip_counts(character):
                with Image.open(ROOT/'output/imagegen/anime-v2/review'/(character+'-'+clip+'.gif')) as preview:
                    self.assertTrue(preview.is_animated)
                    self.assertEqual(preview.n_frames, clip_counts(character)[clip])
                    self.assertGreater(preview.info.get('duration',0),0)

if __name__ == '__main__':
    if '--with-previews' in sys.argv:
        CHECK_PREVIEWS = True
        sys.argv.remove('--with-previews')
    unittest.main(verbosity=2)
