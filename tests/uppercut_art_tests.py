"""Pixel-level regression checks for the three reported Nezuko size transitions."""
from pathlib import Path
import sys,unittest
import cv2,numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from review_roster_scale import Atlas

def face_span(image):
 a=np.array(image).astype(np.int16)
 mask=(a[:,:,3]>180)&(a[:,:,0]>224)&(a[:,:,1]>180)&(a[:,:,2]>145)&(a[:,:,0]>a[:,:,1]+8)&(a[:,:,1]>a[:,:,2]+5)
 mask=cv2.morphologyEx(mask.astype(np.uint8),cv2.MORPH_CLOSE,np.ones((2,2),np.uint8))
 count,labels,stats,centres=cv2.connectedComponentsWithStats(mask,8)
 candidates=[k for k in range(1,count) if stats[k,4]>35]
 selected=min(candidates,key=lambda k:stats[k,1])
 ys,xs=np.where(labels==selected)
 return max(cv2.minAreaRect(np.column_stack((xs,ys)).astype(np.float32))[1])

class UppercutArtTests(unittest.TestCase):
 def setUp(self):self.atlas=Atlas(ROOT/'art/characters/nezuko')
 def tearDown(self):self.atlas.close()
 def test_standing_kicks_keep_neutral_stature_and_feet(self):
  idle=self.atlas.frame('idle',0);b=idle.getbbox();height=b[3]-b[1]
  for clip in ['body_stand_light','body_stand_heavy']:
   for index in range(6):
    bounds=self.atlas.frame(clip,index).getbbox()
    ratio=(bounds[3]-bounds[1])/height
    self.assertGreater(ratio,.98,(clip,index,ratio))
    self.assertLess(ratio,1.04,(clip,index,ratio))
    self.assertLessEqual(abs(bounds[3]-self.atlas.data['feet_anchor'][1]),1)
 def test_crouch_guard_keeps_head_scale_and_foot_contact(self):
  reference=face_span(self.atlas.frame('idle',0))
  # Other drawings join the guarding hand to the face's skin-color component;
  # use the four frames with an independently exposed face as an anatomy ruler.
  for index in [1,3,4,5]:
   ratio=face_span(self.atlas.frame('guard_low',index))/reference
   self.assertGreater(ratio,.90,(index,ratio))
   self.assertLess(ratio,1.06,(index,ratio))
  for index in range(6):
   bounds=self.atlas.frame('guard_low',index).getbbox()
   self.assertLessEqual(abs(bounds[3]-self.atlas.data['feet_anchor'][1]),1)

 def test_zenitsu_replacement_is_calibrated_generated_art(self):
  import json,hashlib
  from PIL import Image
  folder=ROOT/'output/imagegen/uppercut-v1'
  jobs=json.loads((folder/'jobs.json').read_text(encoding='utf-8'))
  atlas=Atlas(ROOT/'art/characters/zenitsu')
  try:
   for job in jobs:
    record=json.loads((folder/'records'/(job['id']+'.json')).read_text(encoding='utf-8-sig'))
    spec=json.loads((folder/'imports'/(job['id']+'.json')).read_text(encoding='utf-8'))
    self.assertEqual(record['status'],'generated');self.assertTrue(record['accepted'])
    self.assertEqual(record['sha256'],hashlib.sha256((ROOT/job['out']).read_bytes()).hexdigest())
    with Image.open(ROOT/job['out']) as im:self.assertEqual(list(im.size),record['actual_size'])
    self.assertEqual(len(spec['frames']),9)
    self.assertEqual(len({frame['scale'] for frame in spec['frames']}),1,'one physical scale across the authored uppercut')
    for index,frame in enumerate(spec['frames']):
     if frame['source_pelvis_y'] is not None:
      self.assertAlmostEqual((frame['source_pelvis_y']-frame['source_root'][1])*frame['scale'],-34/70*340,places=3)
     else:self.assertLessEqual(abs(frame['normalized_bounds'][3]-568),2)
     image=atlas.frame('iai',index)
     a=np.array(image).astype(np.int16)
     green=(a[:,:,1]-np.maximum(a[:,:,0],a[:,:,2])>100)&(a[:,:,3]>160)
     self.assertLess(green.sum()/max(1,(a[:,:,3]>160).sum()),.002,'no visible key-color fringe')
    baseline=atlas.frame('idle',0).getbbox()
    for index in [0,8]:
     pose=atlas.frame('iai',index).getbbox();ratio=(pose[3]-pose[1])/(baseline[3]-baseline[1])
     self.assertGreater(ratio,.98);self.assertLess(ratio,1.03)
  finally:atlas.close()

if __name__=='__main__':unittest.main()

