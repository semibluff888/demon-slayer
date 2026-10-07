"""Checks shipped alternate atlases, timing, registration, and provenance."""
import hashlib,json,unittest
import numpy as np
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/awakening-v1'
V2=ROOT/'output/imagegen/awakening-v2'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
class AwakeningArtTests(unittest.TestCase):
 def test_jobs_complete_and_registered(self):
  selection=read(OUT/'selected.json') if (OUT/'selected.json').exists() else {}
  for base in read(OUT/'jobs.json'):
   job=dict(base);job.update(selection.get(base['id'],{}))
   with self.subTest(job=job['id']):
    raw=ROOT/job['out'];self.assertTrue(raw.exists())
    record=read(OUT/'records'/(job['id']+'.json'));self.assertEqual(record['status'],'generated')
    registration=read(OUT/'imports'/(base['id']+'.json'))
    self.assertEqual(registration['source'],job['out'])
    self.assertEqual(registration['source_sha256'],hashlib.sha256(raw.read_bytes()).hexdigest())
    self.assertEqual(len(registration['frames']),job['metadata']['count'])
    pixels=np.asarray(Image.open(raw).convert('RGBA')).astype(float)
    removable=(pixels[:,:,3]<8)|(np.minimum(pixels[:,:,1],pixels[:,:,2])-pixels[:,:,0]>100)
    self.assertGreater(np.mean(removable),.3,'Source requires native transparency or removable cyan')
 def test_v2_sources_and_preserved_akaza(self):
  selection=read(V2/'selected.json') if (V2/'selected.json').exists() else {}
  for base in read(V2/'jobs.json'):
   job=dict(base);job.update(selection.get(base['id'],{}))
   with self.subTest(job=job['id']):
    raw=ROOT/job['out'];self.assertTrue(raw.exists())
    record=read(V2/'records'/(job['id']+'.json'));self.assertEqual(record['status'],'generated')
    registration=read(V2/'imports'/(base['id']+'.json'))
    self.assertEqual(registration['source_sha256'],hashlib.sha256(raw.read_bytes()).hexdigest())
    atlas=read(ROOT/'art/characters'/job['metadata']['character']/'awakening/atlas.json')
    self.assertEqual(atlas['revision'],'awakening-v2')
    packed=atlas['clips'][job['metadata']['clip']]['frames']
    self.assertEqual(len(packed),len(registration['frames']))
    for frame,calibration in zip(packed,registration['frames']):
     self.assertEqual(frame['offset'],calibration['offset'])
     self.assertEqual(frame['region'][2:],calibration['size'])
  for path,digest in read(V2/'preserved-akaza.json').items():
   self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),digest,path)
 def test_v2_keying_preserves_costume(self):
  import sys
  sys.path.insert(0,str(ROOT/'tools'))
  from build_awakening_art import cyan_matte
  swatches=Image.new('RGBA',(3,1));swatches.putdata([(42,171,135,255),(0,255,255,255),(240,186,76,255)])
  keyed=cyan_matte(swatches)
  self.assertEqual(keyed.getpixel((0,0)),(42,171,135,255))
  self.assertEqual(keyed.getpixel((1,0))[3],0)
  self.assertEqual(keyed.getpixel((2,0)),(240,186,76,255))
 def test_frame_coverage_and_unchanged_timing(self):
  for cid in ['tanjiro','zenitsu','nezuko','akaza']:
   base=ROOT/'art/characters'/cid;normal=read(base/'atlas.json')
   if (base/'round-atlas.json').exists():normal['clips'].update(read(base/'round-atlas.json')['clips'])
   awakened=read(base/'awakening/atlas.json')
   self.assertEqual(normal['feet_anchor'],awakened['feet_anchor'])
   self.assertEqual(normal['source_height'],awakened['source_height'])
   self.assertEqual(normal['canvas_size'],awakened['canvas_size'])
   for clip,meta in normal['clips'].items():
    with self.subTest(character=cid,clip=clip):
     alt=awakened['clips'][clip]
     self.assertEqual(len(meta['frames']),len(alt['frames']))
     for key in ['phase_breaks','segment_sync','timeline','fps','loop','anchor_mode']:
      self.assertEqual(meta.get(key),alt.get(key))
   self.assertEqual(len(awakened['clips']['awakening_start']['frames']),6)
 def test_pages_and_pose_bounds(self):
  for manifest in (ROOT/'art/characters').glob('*/awakening/atlas.json'):
   atlas=read(manifest);cache={}
   for clip,meta in atlas['clips'].items():
    for index,entry in enumerate(meta['frames']):
     with self.subTest(character=manifest.parent.parent.name,clip=clip,index=index):
      path=manifest.parent/entry['texture']
      if path not in cache:
       cache[path]=Image.open(path);self.assertEqual(cache[path].mode,'RGBA')
      page=cache[path];x,y,w,h=entry['region'];ox,oy=entry['offset']
      self.assertGreater(w,0);self.assertGreater(h,0)
      self.assertGreaterEqual(x,0);self.assertGreaterEqual(y,0)
      self.assertLessEqual(x+w,page.width);self.assertLessEqual(y+h,page.height)
      self.assertGreaterEqual(ox,0);self.assertGreaterEqual(oy,0)
      self.assertLessEqual(ox+w,atlas['canvas_size'][0]);self.assertLessEqual(oy+h,atlas['canvas_size'][1])
      self.assertIsNotNone(page.crop((x,y,x+w,y+h)).getbbox())
if __name__=='__main__':unittest.main()
