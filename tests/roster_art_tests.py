"""Offline validation of the shipped expansion sources, mattes and stage seams."""
import hashlib,json,unittest
from pathlib import Path
import numpy as np
import cv2
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/roster-v1'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
# Akaza and Nezuko ship the tools/art_v3 redraw (tests/art_v3_tests.py); their roster-v1 animation
# sources were removed on 2026-10-20. Stages, effects, model sheets and Nezuko's portraits still ship.
def shipped(job):
 return job['group'] in ['foundation','effects','stage-detail'] or (job['group']=='portraits' and job['id'].startswith('nezuko-'))
class ExpansionArtTests(unittest.TestCase):
 def test_sources_are_reproducible(self):
  jobs=[job for job in read(OUT/'jobs.json') if shipped(job)]
  self.assertEqual(len(jobs),30)
  for job in jobs:
   with self.subTest(job=job['id']):
    source=ROOT/job['out'];record=read(OUT/'records'/(job['id']+'.json'))
    self.assertEqual(record['status'],'generated')
    self.assertEqual(record['sha256'],hashlib.sha256(source.read_bytes()).hexdigest())
    with Image.open(source) as original:self.assertEqual(record['actual_size'],list(original.size))
    self.assertTrue((ROOT/job['prompt']).exists())
    for reference in job['references']:self.assertTrue((ROOT/reference).exists())
 def test_stage_tiles_exactly_reconstruct_the_panorama(self):
  for job in read(OUT/'jobs.json'):
   if job['group']!='foundation' or 'stage' not in job['metadata']:continue
   directory=ROOT/'art/stages'/job['metadata']['stage'];meta=read(directory/'stage.json')
   panorama=np.array(Image.open(directory/'panorama.png').convert('RGB'))
   self.assertEqual(list(panorama.shape[:2][::-1]),meta['size'])
   self.assertEqual(len(meta['sources']),10)
   for source in meta['sources']:
    self.assertGreater(source['correlation'],.7)
    self.assertEqual(source['sha256'],hashlib.sha256((ROOT/source['path']).read_bytes()).hexdigest())
   padded=np.pad(panorama,((8,8),(8,8),(0,0)),mode='edge')
   for tile in meta['tiles']:
    x,y,w,h=tile['rect'];actual=np.array(Image.open(directory/tile['texture']).convert('RGB'))
    np.testing.assert_array_equal(actual,padded[y:y+h+16,x:x+w+16])
 def test_cut_in_and_effect_files(self):
  with Image.open(ROOT/'art/characters/nezuko/awakened-portrait.png') as cut_in:
   mask=(np.array(cut_in.getchannel('A'))>160).astype(np.uint8)
   count,labels,stats,centres=cv2.connectedComponentsWithStats(mask,8)
   areas=stats[1:,4]
   self.assertEqual(sum(areas>areas.max()*.20),1,'MAX cut-in contains exactly one character')
  for key in ['blood-flame','shockwave','compass']:
   with Image.open(ROOT/'art/effects'/(key+'-body.png')) as image:
    self.assertEqual(image.mode,'RGBA');self.assertLess(image.getchannel('A').getextrema()[0],10)
if __name__=='__main__':unittest.main()
