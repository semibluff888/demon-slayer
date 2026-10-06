# coding: utf-8
"""Checks delivered bitmap provenance and seamless runtime stage tiles."""
from pathlib import Path
import hashlib,json,unittest
import numpy as np
from PIL import Image
from fontTools.ttLib import TTFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/fate-v1'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
class FateArtTests(unittest.TestCase):
 def test_generated_assets_have_exact_source_records(self):
  for job in read(OUT/'jobs.json')+read(ROOT/'output/imagegen/menu-settings-v1/jobs.json'):
   path=ROOT/job['out'];record=read((ROOT/job['prompt']).parents[1]/'records'/(job['id']+'.json'))
   with Image.open(path) as source:self.assertEqual(list(source.size),record['actual_size'])
   self.assertEqual(record['sha256'],hashlib.sha256(path.read_bytes()).hexdigest())
   self.assertTrue(record['accepted']);self.assertEqual(record['status'],'generated')
   self.assertTrue((ROOT/job['prompt']).is_file())
  with Image.open(ROOT/'output/imagegen/menu-settings-v1/raw/title-ensemble-v2.png') as source,Image.open(ROOT/'art/ui/title-poster.png') as runtime:
   np.testing.assert_array_equal(np.array(source.convert('RGB')),np.array(runtime.convert('RGB')))
   self.assertAlmostEqual(runtime.width/runtime.height,16/9,places=2)
 def test_courtyard_tiles_exactly_reconstruct_the_reviewed_pixels(self):
  folder=ROOT/'art/stages/corps_courtyard';meta=read(folder/'stage.json')
  with Image.open(folder/'panorama.png') as im:panorama=np.array(im.convert('RGB'))
  self.assertEqual(meta['size'],[panorama.shape[1],panorama.shape[0]])
  source=meta['sources'][0]
  with Image.open(ROOT/source['path']) as im:crop=np.array(im.convert('RGB').crop(source['crop']))
  np.testing.assert_array_equal(crop,panorama)
  self.assertEqual(meta['render_size'],[3168,792]);self.assertEqual(meta['world_width'],960)
  self.assertEqual(len(meta['tiles']),4)
  padded=np.pad(panorama,((8,8),(8,8),(0,0)),mode='edge')
  width=0
  for tile in meta['tiles']:
   x,y,w,h=tile['rect'];width+=w
   with Image.open(folder/tile['texture']) as im:actual=np.array(im.convert('RGB'))
   np.testing.assert_array_equal(actual,padded[y:y+h+16,x:x+w+16])
   self.assertEqual(tile['region'],[8,8,w,h])
  self.assertEqual(width,meta['size'][0])
 def test_courtyard_super_resolution_provenance_and_offline_dependencies(self):
  folder=ROOT/'output/imagegen/courtyard-hd-v1'
  record=read(folder/'processing.json')
  meta=read(ROOT/'art/stages/corps_courtyard/stage.json')
  master=ROOT/record['source'];processed=ROOT/record['output']
  self.assertEqual(meta['revision'],'courtyard-sr-v1')
  self.assertEqual(record['status'],'processed')
  self.assertEqual(record['method'],'neural-super-resolution')
  self.assertTrue(record['accepted'])
  self.assertEqual(record['source_sha256'],hashlib.sha256(master.read_bytes()).hexdigest())
  self.assertEqual(record['sha256'],hashlib.sha256(processed.read_bytes()).hexdigest())
  with Image.open(master) as original,Image.open(processed) as detailed:
   self.assertEqual(list(original.size),record['generated_size'])
   self.assertEqual(list(detailed.size),record['actual_size'])
   self.assertEqual(list(detailed.size),[value*4 for value in original.size])
   self.assertEqual(list(original.size),read(OUT/'records/corps-courtyard.json')['actual_size'])
  original_crop=read(OUT/'imports/corps-courtyard.json')['source']['crop']
  self.assertEqual(record['crop'],[value*4 for value in original_crop])
  self.assertEqual(meta['size'],[8688,2172])
  source=meta['sources'][0]
  self.assertEqual(source['generated_master'],record['source'])
  self.assertEqual(source['generated_size'],record['generated_size'])
  self.assertEqual(source['method'],record['method'])
  self.assertEqual(source['sha256'],record['sha256'])
  distribution=read(ROOT/record['distribution'])
  self.assertTrue(distribution['files'])
  for dependency in distribution['files']:
   file=ROOT/dependency['path']
   self.assertEqual(file.stat().st_size,dependency['size_bytes'])
   self.assertEqual(hashlib.sha256(file.read_bytes()).hexdigest(),dependency['sha256'])
  for tile in meta['tiles']:
   settings=(ROOT/'art/stages/corps_courtyard'/(tile['texture']+'.import')).read_text()
   self.assertIn('mipmaps/generate=true',settings)
   self.assertIn('process/size_limit=0',settings)

 def test_menu_fonts_cover_the_new_stage(self):
  needed='\u9b3c\u6740\u961f\u5ead\u9662\u6668\u5149\u9759\u5ead'
  for file in ['NotoSansSC-ui.ttf','NotoSerifSC-title.ttf']:
   with TTFont(ROOT/'art/fonts'/file) as font:
    cmap=font.getBestCmap()
    self.assertTrue(all(ord(char) in cmap for char in needed))
if __name__=='__main__':unittest.main()
