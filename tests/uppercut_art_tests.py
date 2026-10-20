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

# Nezuko's v3 redraw (tests/art_v3_tests.py) replaces the registered guard redraw; her
# standing kicks still keep the idle's height (the user asked for one height, 2026-10-18).
NEZUKO_V3=__import__('json').loads((ROOT/'art/characters/nezuko/atlas.json').read_text(encoding='utf-8')).get('revision')=='nezuko-v3'

class UppercutArtTests(unittest.TestCase):
 def setUp(self):self.atlas=Atlas(ROOT/'art/characters/nezuko')
 def tearDown(self):self.atlas.close()
 def test_standing_kicks_keep_neutral_stature_and_feet(self):
  idle=self.atlas.frame('idle',0);b=idle.getbbox();height=b[3]-b[1]
  low,clips=(.96,['body_stand_light','body_stand_heavy','renzoku_2']) if NEZUKO_V3 else (.98,['body_stand_light','body_stand_heavy'])
  for clip in clips:
   for index in range(len(self.atlas.data['clips'][clip]['frames'])):
    bounds=self.atlas.frame(clip,index).getbbox()
    ratio=(bounds[3]-bounds[1])/height
    self.assertGreater(ratio,low,(clip,index,ratio))
    self.assertLess(ratio,1.04,(clip,index,ratio))
    self.assertLessEqual(abs(bounds[3]-self.atlas.data['feet_anchor'][1]),1)

if __name__=='__main__':unittest.main()

