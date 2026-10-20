"""Checks shipped alternate atlases, timing, registration, and provenance."""
import hashlib,json,unittest
import numpy as np
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
# Nezuko's shipped demon form. Its baseline/ is the complete earlier atlas; the superseded
# v1-v8 production folders were removed on 2026-10-20 (docs/cleanup-2026-10-20.md).
V9=ROOT/'output/imagegen/awakening-v9'
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
class AwakeningArtTests(unittest.TestCase):
 def test_current_sources(self):
  # A character redrawn with tools/art_v3 derives its awakened atlas from the new
  # base art; tests/art_v3_tests.py checks it.
  for cid in ['tanjiro','zenitsu','akaza']:
   self.assertEqual(read(ROOT/'art/characters'/cid/'atlas.json')['revision'],cid+'-v3')
   self.assertEqual(read(ROOT/'art/characters'/cid/'awakening/atlas.json')['revision'],cid+'-v3')
  # Nezuko's demon form was not redrawn: her shipped awakened atlas stays beside the v3 normal one.
  self.assertEqual(read(ROOT/'art/characters/nezuko/atlas.json')['revision'],'nezuko-v3')
  atlas=read(ROOT/'art/characters/nezuko/awakening/atlas.json')
  self.assertEqual(atlas['revision'],'awakening-v9')
  self.assertLessEqual(set(read(V9/'baseline/atlas.json')['clips']),set(atlas['clips']))
 def test_preserves_approved_max_and_all_untargeted_drawings(self):
  current=ROOT/'art/characters/nezuko/awakening'
  pages={}
  def pixels(directory,entry):
   path=directory/entry['texture']
   if path not in pages:
    with Image.open(path) as im:pages[path]=im.convert('RGBA')
   x,y,w,h=entry['region'];return pages[path].crop((x,y,x+w,y+h)).tobytes()
  targets={'stand_heavy','rising_kick','blood_kick','guard_low','throw_forward','throw_success','spinning_kick','blood_burst'}
  old=read(V9/'baseline/atlas.json');new=read(current/'atlas.json');preserved=0
  for clip,meta in old['clips'].items():
   expected={k:v for k,v in meta.items() if k!='frames'}
   if clip in ['walk','walk_back']:expected['fps']=12
   self.assertEqual(expected,{k:v for k,v in new['clips'][clip].items() if k!='frames'})
   if clip in targets:continue
   for before,after in zip(meta['frames'],new['clips'][clip]['frames']):
    with self.subTest(preserved_clip=clip,frame=preserved):
     self.assertEqual(before['offset'],after['offset']);self.assertEqual(before['region'][2:],after['region'][2:])
     self.assertEqual(pixels(V9/'baseline',before),pixels(current,after));preserved+=1
  # Includes the approved idle and MAX (awakened_combo) drawings.
  self.assertEqual(preserved,270)
  # Ready / fully recovered poses must transition to idle without a size pop.
  atlas=read(current/'atlas.json');idle=atlas['clips']['idle']['frames'][0]
  for clip in ['stand_heavy','rising_kick','blood_kick','throw_forward','spinning_kick','blood_burst']:
   frames=atlas['clips'][clip]['frames']
   for frame in ([frames[-1]] if clip in ['spinning_kick','blood_burst'] else [frames[0],frames[-1]]):
    self.assertEqual(frame['offset'],idle['offset']);self.assertEqual(frame['region'][2:],idle['region'][2:])
    self.assertEqual(pixels(current,frame),pixels(current,idle))
  for clip in ['stand_heavy','rising_kick','blood_kick','guard_low','throw_forward','throw_success']:
   record=read(V9/'imports'/('nezuko-'+clip+'.json'))
   if clip in ['blood_kick','throw_forward','throw_success']:
    record={'frames':[{'offset':e['offset'],'size':e['region'][2:]} for e in read(ROOT/'output/imagegen/motion-fixes-v1/imports/nezuko-awakening.json')['clips'][clip]['frames']]}
   for frame,registration in zip(atlas['clips'][clip]['frames'],record['frames']):
    self.assertEqual(frame['offset'],registration['offset']);self.assertEqual(frame['region'][2:],registration['size'])
  # Back throw starts toward the victim and finishes facing the landing side.
  # Runtime keeps throw_facing fixed until the throw ends, then faces the victim.
  forward=atlas['clips']['throw_forward']['frames'];back=atlas['clips']['throw_success']['frames']
  for i in list(range(4))+list(range(6,12)):
   src=forward[i];dst=back[i];w,h=src['region'][2:]
   source_image=Image.frombytes('RGBA',(w,h),pixels(current,src))
   if i>=6:source_image=source_image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
   self.assertEqual(source_image.tobytes(),pixels(current,dst))
   expected_x=2*atlas['feet_anchor'][0]-src['offset'][0]-w if i>=6 else src['offset'][0]
   self.assertEqual(dst['offset'],[expected_x,src['offset'][1]])
  for entry in forward+back:self.assertEqual(entry['offset'][1]+entry['region'][3],569)
  guard=read(V9/'corrections.json')['guard']
  for key in ['original','edited']:self.assertEqual(hashlib.sha256((ROOT/guard[key]).read_bytes()).hexdigest(),guard[key+'_sha256'])
  source=np.array(Image.open(ROOT/guard['original']));patched=np.array(Image.open(V9/'raw/nezuko-guard_low-patched.png'))
  mask=np.zeros(source.shape[:2],dtype=bool)
  for x,y,r,b in guard['patch_boxes']:mask[max(0,y-5):b+6,max(0,x-5):r+6]=True
  self.assertTrue(np.array_equal(source[~mask,:3],patched[~mask,:3]),'Guard edit must stay local to the hands/forearms')
 def test_walk_has_stable_stature_and_no_root_jump(self):
  atlas=read(ROOT/'art/characters/nezuko/awakening/atlas.json')
  for clip in ['walk','walk_back']:
   # The v8 walk registration, kept beside the baseline whose drawings it placed.
   entries=atlas['clips'][clip]['frames'];model=read(V9/'baseline'/('nezuko-'+clip+'-import.json'))['frames']
   heights=[e['region'][3] for e in entries]
   self.assertLessEqual(max(heights)-min(heights),3);self.assertTrue(all(354<=h<=357 for h in heights))
   self.assertTrue(all(e['offset'][1]+e['region'][3]==569 for e in entries))
   roots=[e['offset'][0]+(f['source_root_absolute'][0]-f['source_origin'][0])*f['scale'] for e,f in zip(entries,model)]
   self.assertTrue(all(abs(x-449)<=.5 for x in roots))
   self.assertTrue(all(abs(roots[i]-roots[(i+1)%6])<1 for i in range(6)),'Includes last-to-first seam')
 def test_head_ruler_does_not_follow_silhouette(self):
  import sys
  sys.path.insert(0,str(ROOT/'tools'))
  from awakening_anatomy import register
  # Simulate a cape/hair extension and a compact pose at the SAME skull size.
  model={'head_lengths':[90]};base=Image.new('RGBA',(200,400),(100,20,40,255))
  for width,height in [(200,400),(800,400),(180,160),(500,100)]:
   image=Image.new('RGBA',(width,height),(100,20,40,255))
   scale,size,offset,details=register(image,0,59.5,model,base,(350,160),[350,160,550,560])
   self.assertAlmostEqual(scale,59.5/90)
   self.assertEqual(offset[1]+size[1],560,'Ground contact must not drift')
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
   # A kept form atlas (Nezuko's demon form beside her v3 redraw) keeps its own drawings and
   # timing; FighterView reads each atlas's own breaks, so it only has to cover every clip.
   if normal.get('revision')==cid+'-v3' and awakened.get('revision')!=cid+'-v3':
    for clip,meta in normal['clips'].items():
     with self.subTest(character=cid,clip=clip):
      alt=awakened['clips'][clip];self.assertGreater(len(alt['frames']),0)
      self.assertLessEqual(max(alt.get('phase_breaks',[0])),len(alt['frames']))
    self.assertEqual(len(awakened['clips']['awakening_start']['frames']),6)
    continue
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
