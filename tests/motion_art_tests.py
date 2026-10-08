"""Verify targeted art edits and that unrelated poses retain exact pixels/metadata."""
import json, unittest
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/motion-fixes-v1'
TARGETS={'nezuko/awakening':{'blood_kick','spinning_kick','blood_burst','throw_forward','throw_success'},'nezuko':{'blood_burst','throw_forward','throw_success'},'akaza':{'throw_forward','throw_success'},'akaza/awakening':{'throw_forward','throw_success'},'zenitsu':{'throw_success'},'zenitsu/awakening':{'throw_success'}}
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sprite(folder,e):
 x,y,w,h=e['region']
 with Image.open(folder/e['texture']) as im:return im.convert('RGBA').crop((x,y,x+w,y+h))
class MotionArtTests(unittest.TestCase):
 def test_only_requested_clips_change(self):
  for key,targets in TARGETS.items():
   folder=ROOT/'art/characters'/key;old=read(OUT/'baseline'/key/'atlas.json');new=read(folder/'atlas.json')
   self.assertEqual(set(old['clips']),set(new['clips']))
   for c in old['clips']: 
    if c not in targets:self.assertEqual(old['clips'][c],new['clips'][c],key+'/'+c)
   for field in ['canvas_size','feet_anchor','source_height','canonical_height']:self.assertEqual(old[field],new[field])
 def test_return_to_exact_idle(self):
  for key,clips in {'nezuko/awakening':['blood_kick','spinning_kick','blood_burst','throw_forward'],'nezuko':['blood_burst','throw_forward'],'akaza':['throw_forward'],'akaza/awakening':['throw_forward']}.items():
   folder=ROOT/'art/characters'/key;m=read(folder/'atlas.json');idle=m['clips']['idle']['frames'][0]
   for c in clips:
    end=m['clips'][c]['frames'][-1];self.assertEqual(end['offset'],idle['offset']);self.assertEqual(sprite(folder,end).tobytes(),sprite(folder,idle).tobytes())
 def test_back_throw_has_shared_grab_and_mirrored_release(self):
  for key in ['nezuko','nezuko/awakening','akaza','akaza/awakening']:
   folder=ROOT/'art/characters'/key;m=read(folder/'atlas.json');fw=m['clips']['throw_forward']['frames'];bk=m['clips']['throw_success']['frames'];turn=3 if key.startswith('akaza') else 6
   for i in range(len(fw)):
    if key.startswith('nezuko') and i in [4,5]:continue
    source=sprite(folder,fw[i]);x,y=fw[i]['offset']
    if i>=turn:source=source.transpose(Image.Transpose.FLIP_LEFT_RIGHT);x=2*m['feet_anchor'][0]-x-source.width
    self.assertEqual(source.tobytes(),sprite(folder,bk[i]).tobytes(),key+'/'+str(i));self.assertEqual([x,y],bk[i]['offset'])
 def test_akaza_timeline_and_anatomy(self):
  for key in ['akaza','akaza/awakening']:
   folder=ROOT/'art/characters'/key;m=read(folder/'atlas.json')
   for c in ['throw_forward','throw_success']:
    self.assertEqual(m['clips'][c]['timeline'],[0,3,8,10,15,20,23,29]);self.assertEqual(len(m['clips'][c]['frames']),8)
    for e in m['clips'][c]['frames']:self.assertEqual(e['offset'][1]+e['region'][3],569)
  for frame in read(OUT/'imports/akaza-generated.json')['frames']:self.assertAlmostEqual(frame['head_length']*frame['scale'],70)
 def test_zenitsu_turn_stays_reversed_through_recovery(self):
  for key in ['zenitsu','zenitsu/awakening']:
   folder=ROOT/'art/characters'/key;m=read(folder/'atlas.json');b=OUT/'baseline'/key;old=read(b/'atlas.json')
   for i in [5,6,8,9,10,11]:
    source=Image.open(b/f'throw_success-{i}.png').convert('RGBA');target=m['clips']['throw_success']['frames'][i]
    self.assertEqual(source.transpose(Image.Transpose.FLIP_LEFT_RIGHT).tobytes(),sprite(folder,target).tobytes())
    self.assertEqual(target['offset'],[2*m['feet_anchor'][0]-old['clips']['throw_success']['frames'][i]['offset'][0]-source.width,old['clips']['throw_success']['frames'][i]['offset'][1]])
if __name__=='__main__':unittest.main()
