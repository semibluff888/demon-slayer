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
 def test_current_sources_and_preserved_characters(self):
  revisions={'tanjiro':'awakening-v2','zenitsu':'awakening-v2','nezuko':'awakening-v9'}
  for cid,revision in revisions.items():
   production=ROOT/'output/imagegen'/('awakening-v8' if cid=='nezuko' else revision)
   atlas=read(ROOT/'art/characters'/cid/'awakening/atlas.json')
   self.assertEqual(atlas['revision'],revision)
   if cid=='nezuko':atlas=read(ROOT/'output/imagegen/awakening-v9/baseline/atlas.json')
   jobs=[(production,j) for j in read(production/'jobs.json') if j['metadata']['character']==cid]
   if cid=='nezuko':
    previous=ROOT/'output/imagegen/awakening-v7';replaced={j['metadata']['clip'] for _,j in jobs}
    jobs += [(previous,j) for j in read(previous/'jobs.json') if j['metadata']['clip'] not in replaced]
   normal=read(ROOT/'art/characters'/cid/'atlas.json')
   expected=(set(normal['clips'])-{'victory','round_intro','round_victory','round_defeat'})|{'awakening_start'}
   self.assertEqual({job['metadata']['clip'] for _,job in jobs},expected)
   for source_dir,base in jobs:
    selection=read(source_dir/'selected.json') if (source_dir/'selected.json').exists() else {}
    job=dict(base);job.update(selection.get(base['id'],{}))
    with self.subTest(revision=revision,job=job['id']):
     raw=ROOT/job['out'];self.assertTrue(raw.exists())
     record=read(source_dir/'records'/(job['id']+'.json'));self.assertIn(record['status'],['generated','assembled'])
     for sheet in record.get('sources',[]):
      self.assertEqual(read(source_dir/'records'/(sheet['id']+'.json'))['status'],'generated')
      self.assertEqual(hashlib.sha256((ROOT/sheet['out']).read_bytes()).hexdigest(),sheet['source_sha256'])
     registration=read(source_dir/'imports'/(base['id']+'.json'))
     self.assertEqual(registration['source'],job['out'])
     self.assertEqual(registration['source_sha256'],hashlib.sha256(raw.read_bytes()).hexdigest())
     packed=atlas['clips'][job['metadata']['clip']]['frames']
     self.assertEqual(len(packed),job['metadata']['count'])
     self.assertEqual(len(packed),len(registration['frames']))
     for frame,calibration in zip(packed,registration['frames']):
      self.assertEqual(frame['offset'],calibration['offset'])
      self.assertEqual(frame['region'][2:],calibration['size'])
  for baseline in [V2/'preserved-akaza.json']+[ROOT/('output/imagegen/awakening-v%d/preserved-runtime.json'%v) for v in [6,7,8]]:
   for path,digest in read(baseline).items():
    self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),digest,path)
 def test_preserves_approved_max_and_all_untargeted_drawings(self):
  current=ROOT/'art/characters/nezuko/awakening';v8=ROOT/'output/imagegen/awakening-v8';v9=ROOT/'output/imagegen/awakening-v9'
  pages={}
  def pixels(directory,entry):
   path=directory/entry['texture']
   if path not in pages:
    with Image.open(path) as im:pages[path]=im.convert('RGBA')
   x,y,w,h=entry['region'];return pages[path].crop((x,y,x+w,y+h)).tobytes()
  for before_dir,after_dir,targets,total in [(v8/'baseline',v9/'baseline',set(read(v8/'master.json')['target_clips']),258),(v9/'baseline',current,{'stand_heavy','rising_kick','blood_kick','guard_low','throw_forward','throw_success'},294)]:
   old=read(before_dir/'atlas.json');new=read(after_dir/'atlas.json');preserved=0
   self.assertNotIn('idle',targets);self.assertNotIn('awakened_combo',targets)
   for clip,meta in old['clips'].items():
    expected={k:v for k,v in meta.items() if k!='frames'}
    if before_dir==v8/'baseline' and clip in ['walk','walk_back']:expected['fps']=20
    if before_dir==v9/'baseline' and clip in ['walk','walk_back']:expected['fps']=12
    self.assertEqual(expected,{k:v for k,v in new['clips'][clip].items() if k!='frames'})
    if clip in targets:continue
    for before,after in zip(meta['frames'],new['clips'][clip]['frames']):
     with self.subTest(preserved_clip=clip,frame=preserved):
      self.assertEqual(before['offset'],after['offset']);self.assertEqual(before['region'][2:],after['region'][2:])
      self.assertEqual(pixels(before_dir,before),pixels(after_dir,after));preserved+=1
   self.assertEqual(preserved,total)
  # Ready / fully recovered poses must transition to idle without a size pop.
  atlas=read(current/'atlas.json');idle=atlas['clips']['idle']['frames'][0]
  for clip in ['stand_heavy','rising_kick','blood_kick','throw_forward']:
   frames=atlas['clips'][clip]['frames']
   for frame in [frames[0],frames[-1]]:
    self.assertEqual(frame['offset'],idle['offset']);self.assertEqual(frame['region'][2:],idle['region'][2:])
    self.assertEqual(pixels(current,frame),pixels(current,idle))
  for clip in ['stand_heavy','rising_kick','blood_kick','guard_low','throw_forward','throw_success']:
   record=read(v9/'imports'/('nezuko-'+clip+'.json'))
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
  guard=read(v9/'corrections.json')['guard']
  for key in ['original','edited']:self.assertEqual(hashlib.sha256((ROOT/guard[key]).read_bytes()).hexdigest(),guard[key+'_sha256'])
  source=np.array(Image.open(ROOT/guard['original']));patched=np.array(Image.open(v9/'raw/nezuko-guard_low-patched.png'))
  mask=np.zeros(source.shape[:2],dtype=bool)
  for x,y,r,b in guard['patch_boxes']:mask[max(0,y-5):b+6,max(0,x-5):r+6]=True
  self.assertTrue(np.array_equal(source[~mask,:3],patched[~mask,:3]),'Guard edit must stay local to the hands/forearms')
 def test_v8_walk_has_stable_stature_and_no_root_jump(self):
  production=ROOT/'output/imagegen/awakening-v8';atlas=read(ROOT/'art/characters/nezuko/awakening/atlas.json')
  for clip in ['walk','walk_back']:
   entries=atlas['clips'][clip]['frames'];model=read(production/'imports'/('nezuko-'+clip+'.json'))['frames']
   heights=[e['region'][3] for e in entries]
   self.assertLessEqual(max(heights)-min(heights),3);self.assertTrue(all(354<=h<=357 for h in heights))
   self.assertTrue(all(e['offset'][1]+e['region'][3]==569 for e in entries))
   roots=[e['offset'][0]+(f['source_root_absolute'][0]-f['source_origin'][0])*f['scale'] for e,f in zip(entries,model)]
   self.assertTrue(all(abs(x-449)<=.5 for x in roots))
   self.assertTrue(all(abs(roots[i]-roots[(i+1)%6])<1 for i in range(6)),'Includes last-to-first seam')
 def test_v8_calibration_is_bound_to_selected_sources(self):
  production=ROOT/'output/imagegen/awakening-v8';cal=read(production/'motion-calibration.json')['clips']
  self.assertEqual(len(cal),12);overrides=0
  for key,model in cal.items():
   record=read(production/'imports'/(key+'.json'))
   self.assertEqual(model['source_sha256'],record['source_sha256'])
   for landmark,frame in zip(model['frames'],record['frames']):
    self.assertEqual(frame['registration_profile'],'model-ruler-v8')
    self.assertLessEqual(abs(frame['rendered_root_x']-449),.5)
    if model['anchor']=='waist':self.assertLessEqual(abs(frame['rendered_root_y']-322),.5)
    if 'source_override' in landmark:
     replacement=landmark['source_override'];self.assertEqual(replacement,frame['source_override'])
     self.assertEqual(hashlib.sha256((ROOT/replacement['out']).read_bytes()).hexdigest(),replacement['source_sha256']);overrides+=1
  self.assertEqual(overrides,3)
 def test_approved_idle_is_pixel_identical(self):
  production=ROOT/'output/imagegen/awakening-v7'
  before=read(production/'baseline/atlas.json');after=read(ROOT/'art/characters/nezuko/awakening/atlas.json')
  def frame(directory,entry,canvas_size):
   x,y,w,h=entry['region']
   with Image.open(directory/entry['texture']) as page:tile=page.convert('RGBA').crop((x,y,x+w,y+h))
   canvas=Image.new('RGBA',tuple(canvas_size));canvas.alpha_composite(tile,tuple(entry['offset']));return np.array(canvas)
  for old,new in zip(before['clips']['idle']['frames'],after['clips']['idle']['frames']):
   self.assertTrue(np.array_equal(frame(production/'baseline',old,before['canvas_size']),frame(ROOT/'art/characters/nezuko/awakening',new,after['canvas_size'])))
 def test_head_ruler_does_not_follow_silhouette(self):
  import sys
  sys.path.insert(0,str(ROOT/'tools'))
  from awakening_anatomy import register,calibrated_frames
  from unittest.mock import patch
  # Simulate a cape/hair extension and a compact pose at the SAME skull size.
  model={'head_lengths':[90]};base=Image.new('RGBA',(200,400),(100,20,40,255))
  for width,height in [(200,400),(800,400),(180,160),(500,100)]:
   image=Image.new('RGBA',(width,height),(100,20,40,255))
   scale,size,offset,details=register(image,0,59.5,model,base,(350,160),[350,160,550,560])
   self.assertAlmostEqual(scale,59.5/90)
   self.assertEqual(offset[1]+size[1],560,'Ground contact must not drift')
  production=ROOT/'output/imagegen/awakening-v7'
  job=next(j for j in read(production/'jobs.json') if j['metadata']['clip']=='walk');job['base_id']=job['id']
  target,_=calibrated_frames(ROOT,production,job);self.assertAlmostEqual(target,59.5)
  invalid=read(production/'anatomy-calibration.json');invalid['clips'][job['id']]['source_sha256']='outdated'
  with patch('awakening_anatomy.read',return_value=invalid):
   with self.assertRaisesRegex(ValueError,'older source'):calibrated_frames(ROOT,production,job)
 def test_anatomical_review_covers_all_dynamic_frames(self):
  production=ROOT/'output/imagegen/awakening-v7';calibration=read(production/'anatomy-calibration.json')
  expected={j['id'] for j in read(production/'jobs.json') if j['metadata']['clip']!='idle'}
  self.assertEqual(set(calibration['clips']),expected)
  total=0
  for job in read(production/'jobs.json'):
   if job['metadata']['clip']=='idle':continue
   record=read(production/'imports'/(job['id']+'.json'));model=calibration['clips'][job['id']]
   self.assertEqual(record['source_sha256'],model['source_sha256'])
   self.assertEqual(len(record['frames']),len(model['head_lengths']))
   for frame,length in zip(record['frames'],model['head_lengths']):
    self.assertEqual(frame['registration_profile'],'idle-head-ruler-v7')
    self.assertAlmostEqual(frame['scale'],calibration['target_head_length']/length)
   total+=len(record['frames'])
  self.assertEqual(total,300)
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
