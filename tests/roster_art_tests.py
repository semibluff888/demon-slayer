"""Offline validation of the registered expansion sources, mattes and stage seams."""
import copy,hashlib,json,sys,unittest
from pathlib import Path
import numpy as np
import cv2
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/roster-v1'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
class ExpansionArtTests(unittest.TestCase):
 def test_sources_and_calibration_are_reproducible(self):
  for job in read(OUT/'jobs.json'):
   if job['group'].startswith('rejected'):continue
   with self.subTest(job=job['id']):
    source=ROOT/job['out'];record=read(OUT/'records'/(job['id']+'.json'))
    self.assertEqual(record['status'],'generated')
    self.assertEqual(record['sha256'],hashlib.sha256(source.read_bytes()).hexdigest())
    with Image.open(source) as original:self.assertEqual(record['actual_size'],list(original.size))
    self.assertTrue((ROOT/job['prompt']).exists())
    for reference in job['references']:self.assertTrue((ROOT/reference).exists())
    if job['group']=='animation':
     calibration=read(OUT/'imports'/(job['id']+'.json'))
     self.assertEqual(len(calibration['frames']),job['metadata']['count'])
     self.assertTrue(all(f['scale']>0 and len(f['root'])==2 for f in calibration['frames']))
 def test_each_registered_animation_has_unique_clean_frames(self):
  jobs=[j for j in read(OUT/'jobs.json') if j['group']=='animation']
  for cid in sorted({j['metadata']['character'] for j in jobs}):
   folder=ROOT/'art/characters'/cid;atlas=read(folder/'atlas.json');pages={}
   authored={j['metadata']['clip']:j for j in jobs if j['metadata']['character']==cid}
   self.assertEqual(set(atlas['clips']),set(authored))
   self.assertEqual(atlas['canvas_size'],[1024,640]);self.assertEqual(atlas['feet_anchor'],[448,568])
   for clip,job in authored.items():
    info=atlas['clips'][clip];hashes=set()
    with self.subTest(character=cid,clip=clip):
     expected_count=8 if cid=='akaza' and clip in ['throw_forward','throw_success'] else job['metadata']['count']
     self.assertEqual(len(info['frames']),expected_count)
     for entry in info['frames']:
      path=folder/entry['texture']
      if path not in pages:pages[path]=Image.open(path).convert('RGBA')
      x,y,w,h=entry['region'];ox,oy=entry['offset']
      self.assertTrue(x>=2 and y>=2 and x+w+2<=pages[path].width and y+h+2<=pages[path].height)
      self.assertTrue(ox>=0 and oy>=0 and ox+w<=1024 and oy+h<=640)
      im=pages[path].crop((x,y,x+w,y+h));hashes.add(hashlib.sha256(im.tobytes()).hexdigest())
      a=np.array(im).astype(np.int16);opaque=a[:,:,3]>160
      key=(np.minimum(a[:,:,1],a[:,:,2])-a[:,:,0]>100) if cid=='nezuko' else (a[:,:,1]-np.maximum(a[:,:,0],a[:,:,2])>100)
      self.assertLess((key & opaque).sum()/max(1,opaque.sum()),.002,'visible chroma spill')
     shared_idle=(cid=='akaza' and clip=='throw_forward') or (cid=='nezuko' and clip in ['throw_forward','blood_burst'])
     self.assertEqual(len(hashes),len(info['frames'])-int(shared_idle),'only the identical initial/final idle drawing may repeat')
     if clip.startswith('thrown'):
      for entry in info['frames'][8:]:
       self.assertGreater(entry['region'][2],entry['region'][3]*1.6,'last victim poses must remain horizontal')
     if clip.startswith('roll'):
      self.assertEqual(info['timeline'],[0,1,2,4,6,9,12,15,18,20,23,26])
   for im in pages.values():im.close()
 def test_physical_rulers_on_packed_art(self):
  def head_span(im,cid):
   a=np.array(im).astype(np.int16)
   if cid=='akaza':
    mask=(a[:,:,3]>180)&(a[:,:,0]>150)&(a[:,:,0]-a[:,:,1]>55)&(a[:,:,2]-a[:,:,1]>25)
    limit=np.percentile(a[:,:,0][mask],99)-32
    mask &= a[:,:,0]>limit
   else:
    mask=(a[:,:,3]>180)&(a[:,:,0]>224)&(a[:,:,1]>180)&(a[:,:,2]>145)&(a[:,:,0]>a[:,:,1]+8)&(a[:,:,1]>a[:,:,2]+5)
   mask=cv2.morphologyEx(mask.astype(np.uint8),cv2.MORPH_CLOSE,np.ones((2,2),np.uint8))
   count,labels,stats,centres=cv2.connectedComponentsWithStats(mask,8)
   candidates=[k for k in range(1,count) if stats[k,4]>35]
   # These checked poses expose the hair/forehead above hands and clothing.
   selected=max(candidates,key=lambda k:stats[k,4]) if cid=='akaza' else min(candidates,key=lambda k:stats[k,1])
   ys,xs=np.where(labels==selected)
   return max(cv2.minAreaRect(np.column_stack((xs,ys)).astype(np.float32))[1])
  for cid in ['akaza','nezuko']:
   folder=ROOT/'art/characters'/cid;atlas=read(folder/'atlas.json');pages={}
   def pose(clip,index):
    frame=atlas['clips'][clip]['frames'][index];name=frame['texture']
    if name not in pages:
     with Image.open(folder/name) as im:pages[name]=im.convert('RGBA')
    x,y,w,h=frame['region'];return pages[name].crop((x,y,x+w,y+h))
   with self.subTest(character=cid):
    idle=pose('idle',0);height=idle.height;head=head_span(idle,cid)
    clips=['guard_low','crouch_light','body_crouch_light'] if cid=='akaza' else ['crouch_light','body_crouch_light','body_crouch_heavy']
    for clip in clips:
     for index in range(len(atlas['clips'][clip]['frames'])):
      ratio=head_span(pose(clip,index),cid)/head
      self.assertGreater(ratio,.87,(cid,clip,index,'head shrank',ratio))
      self.assertLess(ratio,1.12,(cid,clip,index,'head enlarged',ratio))
    # A straight grounded body must not be rendered at a child's scale after a throw.
    for clip in ['thrown','thrown_forward']:
     for index in range(8,12):
      frame=atlas['clips'][clip]['frames'][index];length=frame['region'][2]
      self.assertGreater(length/height,.94,(cid,clip,index,'prone body shrank'))
      self.assertLess(length/height,1.14,(cid,clip,index,'prone body enlarged'))
      self.assertLessEqual(abs(frame['offset'][1]+frame['region'][3]-atlas['feet_anchor'][1]),2)
    for clip in ['crouch','round_defeat']:
     self.assertLess(pose(clip,0).height/height,1.06,(cid,clip,'upright transition enlarged'))
   for im in pages.values():im.close()
 def test_reviewed_scale_is_required_for_every_source(self):
  sys.path.insert(0,str(ROOT/'tools'))
  from build_roster_art import body_scales
  calibration=read(OUT/'scale-calibration.json')
  jobs=[j for j in read(OUT/'jobs.json') if j['group']=='animation']
  self.assertEqual(set(calibration['clips']),{j['id'] for j in jobs})
  for job in jobs:
   model,scales=body_scales(job,calibration)
   self.assertEqual(len(scales),job['metadata']['count'])
   self.assertTrue(all(0<value<2 for value in scales))
  job=jobs[0]
  with self.assertRaisesRegex(ValueError,'Missing body-scale'):body_scales(job,{})
  stale=copy.deepcopy(calibration);stale['clips'][job['id']]['source_sha256']='stale'
  with self.assertRaisesRegex(ValueError,'older source'):body_scales(job,stale)
  incomplete=copy.deepcopy(calibration);incomplete['clips'][job['id']]['frame_multipliers'].pop()
  with self.assertRaisesRegex(ValueError,'Incomplete drawing'):body_scales(job,incomplete)
 def test_rotating_pelvis_does_not_inherit_the_drawing_scale(self):
  calibration=read(OUT/'calibration.json')
  for job in read(OUT/'jobs.json'):
   if job['group']!='animation' or not job['metadata']['clip'].startswith('thrown'):continue
   imported=read(OUT/'imports'/(job['id']+'.json'))
   for index,source_point in calibration[job['id']]['source_pelvis'].items():
    frame=imported['frames'][int(index)]
    pelvis_y=(source_point[1]-frame['crop'][1]-frame['root'][1])*frame['scale']
    self.assertAlmostEqual(pelvis_y,-34/70*340,places=3)
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
