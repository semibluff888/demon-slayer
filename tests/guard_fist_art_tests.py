"""The retained awakened hand patch may not alter body or animation metadata.

Normal guard was subsequently replaced by the complete v3 redraw.
"""
import hashlib,json,unittest
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/guard-hands-v2'
BASE=ROOT/'output/imagegen/guard-fist-v1/baseline'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
class GuardFistTests(unittest.TestCase):
 def test_only_reviewed_hand_pixels_change(self):
  for form in ['awakening']:
   folder=ROOT/'art/characters/nezuko'/('awakening' if form=='awakening' else '')
   old=read(BASE/form/'clip.json');new=read(folder/'atlas.json')['clips']['guard_low']
   self.assertEqual({k:v for k,v in old.items() if k!='frames'},{k:v for k,v in new.items() if k!='frames'})
   self.assertEqual(len(old['frames']),6);self.assertEqual(len(new['frames']),6)
   for i,record in enumerate(read(OUT/f'{form}-patches.json')['frames']):
    with self.subTest(form=form,frame=i):
     e=new['frames'][i];x,y,w,h=e['region'];source=BASE/form/f'{i}.png'
     before=np.array(Image.open(source).convert('RGBA'))
     after=np.array(Image.open(folder/e['texture']).convert('RGBA').crop((x,y,x+w,y+h)))
     mask_path=OUT/'frames'/form/f'{i}-mask.png';mask=np.array(Image.open(mask_path))>0
     self.assertEqual(sha(source),record['source_sha256']);self.assertEqual(sha(mask_path),record['mask_sha256'])
     self.assertEqual(before.shape,after.shape);self.assertEqual(e['offset'],old['frames'][i]['offset'])
     self.assertTrue(np.array_equal(before[~mask],after[~mask]),'All RGBA bytes outside hands must remain exact')
     polygon=Image.new('L',(w,h));ImageDraw.Draw(polygon).polygon([tuple(point) for point in record['polygon']],fill=255)
     self.assertFalse(np.any(mask&(np.array(polygon)==0)))
     self.assertLess(int(mask.sum()),750,'Keep the edit confined to a small hand, not face or forearm')
     count=int(np.any(before!=after,axis=2).sum())
     self.assertEqual(count,record['changed_pixels']);self.assertGreater(count,150)
     self.assertLess(count,before.shape[0]*before.shape[1]*0.02)
 def test_generated_source_and_packed_pixels(self):
  for form in ['awakening']:
   folder=ROOT/'art/characters/nezuko'/('awakening' if form=='awakening' else '')
   record=read(OUT/f'{form}-patches.json')
   self.assertEqual(sha(ROOT/record['generated_source']),record['generated_sha256'])
   for i,e in enumerate(read(folder/'atlas.json')['clips']['guard_low']['frames']):
    frame=OUT/'frames'/form/f'{i}.png';self.assertEqual(sha(frame),record['frames'][i]['result_sha256'])
    x,y,w,h=e['region']
    actual=Image.open(folder/e['texture']).convert('RGBA').crop((x,y,x+w,y+h))
    self.assertEqual(actual.tobytes(),Image.open(frame).convert('RGBA').tobytes())
if __name__=='__main__':unittest.main()
