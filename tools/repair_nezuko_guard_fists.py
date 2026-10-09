"""Offline CPA hand import. Preserve all original pixels outside hand masks."""
import hashlib,json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/guard-hands-v2'
BASE=ROOT/'output/imagegen/guard-fist-v1/baseline'
SOURCE=OUT/'raw/awakening-hands-ipv6.png'
# Left/right wrist joins and upper knuckle, in original-frame coordinates.
SOURCE_POINTS=[[(165,53),(176,59),(178,37)],[(169,56),(179,63),(183,40)],[(178,59),(188,64),(191,44)],[(164,54),(175,61),(179,37)],[(166,56),(176,62),(179,40)],[(165,54),(176,61),(179,37)]]
TARGET_POINTS={
 'normal':[[(211,62),(222,69),(220,47)],[(192,66),(204,73),(204,49)],[(197,67),(208,73),(204,51)],[(198,74),(210,81),(211,58)],[(194,72),(205,79),(205,55)],[(195,70),(207,78),(206,54)]],
 'awakening':[[(165,53),(176,59),(179,37)],[(167,56),(179,62),(182,39)],[(178,60),(188,65),(187,44)],[(164,54),(176,60),(177,37)],[(166,56),(176,62),(178,41)],[(164,54),(176,60),(177,37)]]}
# Reviewed polygons exclude face, rear hand, sleeves and forearm crossing.
POLYGONS={
 'normal':[
 [(209,62),(209,53),(217,43),(225,44),(231,50),(234,60),(229,68),(222,71)],
 [(190,66),(190,56),(199,44),(207,46),(217,56),(219,66),(212,73),(205,76)],
 [(194,67),(193,59),(199,47),(208,48),(217,59),(218,67),(211,75),(208,75)],
 [(197,74),(197,65),(207,55),(215,55),(225,68),(224,77),(215,83),(210,83)],
 [(192,72),(191,64),(202,52),(209,53),(219,65),(219,73),(210,80),(205,81)],
 [(193,70),(193,62),(203,51),(211,52),(222,64),(221,72),(212,79),(207,80)]],
 'awakening':[
 [(163,53),(163,44),(175,33),(184,35),(190,44),(190,53),(178,61),(176,61)],
 [(165,56),(165,47),(177,36),(186,37),(192,46),(192,55),(181,64),(179,64)],
 [(175,60),(175,53),(183,40),(193,42),(201,52),(200,59),(190,67),(188,67)],
 [(162,54),(161,45),(174,32),(182,34),(188,44),(188,53),(178,62),(176,62)],
 [(164,56),(164,46),(175,37),(184,38),(190,46),(189,55),(178,64),(176,64)],
 [(162,54),(161,45),(174,32),(182,34),(189,44),(189,53),(178,62),(176,62)]]}
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def unkey(rgb):
 """Unmix cyan at antialiased edges, returning premultiplied RGBA."""
 c=np.asarray(rgb,dtype=np.float32);opaque=(np.minimum(c[:,:,1],c[:,:,2])-c[:,:,0])<8
 _,labels=cv2.distanceTransformWithLabels((~opaque).astype('uint8'),cv2.DIST_L2,5,labelType=cv2.DIST_LABEL_PIXEL)
 colors=np.zeros((int(labels.max())+1,3),np.float32);colors[labels[opaque]]=c[opaque]
 foreground=colors[labels];bg=np.array([0,255,255],np.float32);direction=foreground-bg
 alpha=np.clip(np.sum((c-bg)*direction,axis=2)/np.maximum(np.sum(direction*direction,axis=2),1),0,1)
 alpha[opaque]=1;alpha[np.max(np.abs(c-bg),axis=2)<8]=0
 color=np.clip((c-bg*(1-alpha[:,:,None]))/np.maximum(alpha[:,:,None],0.001),0,255)
 return np.dstack([color/255*alpha[:,:,None],alpha])
def patch(before,donor,source_points,target_points,polygon):
 # Donor sheet is exactly 2x the sprite. Preserve subpixel center alignment.
 matrix=cv2.getAffineTransform(np.float32(source_points)*2+0.5,np.float32(target_points))
 rgba=cv2.warpAffine(donor,matrix,before.size,flags=cv2.INTER_LINEAR)
 mask_im=Image.new('L',before.size);ImageDraw.Draw(mask_im).polygon(polygon,fill=255)
 mask=np.asarray(mask_im)/255.0;original=np.asarray(before)
 # Select fist skin and its one-pixel ink fringe, protecting other components.
 skin=(original[:,:,0]>205)&(original[:,:,1]>155)&(original[:,:,2]>120)&(original[:,:,3]>150)&(mask>0)
 _,labels,stats,_=cv2.connectedComponentsWithStats(skin.astype('uint8'))
 label=1+np.argmax(stats[1:,4]);fist=(labels==label)
 ink=cv2.dilate(fist.astype('uint8'),np.ones((3,3),np.uint8))>0
 other=cv2.dilate((skin&~fist).astype('uint8'),np.ones((3,3),np.uint8))>0
 mask*=((ink&~other)|(original[:,:,3]==0))
 # Keep the original face-side ink contour and air gap. Finger corrections
 # are on the opposite edge; replacing this border could visually join skin.
 for row in range(before.height):
  xs=np.flatnonzero(fist[row])
  if len(xs) and row>=target_points[2][1]+5:
   mask[row,:int(xs.min())+2]=0
 # Match original skin, retaining generated finger shading and dark ink.
 donor_rgb=rgba[:,:,:3]/np.maximum(rgba[:,:,3:4],0.001)
 sample=fist&(rgba[:,:,3]>0.95)&(donor_rgb[:,:,0]>0.82)&(donor_rgb[:,:,1]>0.60)
 if np.any(sample):
  delta=np.median(original[sample,:3]/255,axis=0)-np.median(donor_rgb[sample],axis=0)
  tone=np.clip((donor_rgb[:,:,0]-0.32)/0.5,0,1)
  donor_rgb=np.clip(donor_rgb+delta*tone[:,:,None],0,1)
  rgba[:,:,:3]=donor_rgb*rgba[:,:,3:4]
 yy,xx=np.mgrid[:before.height,:before.width]
 left,right=np.float32(target_points[:2])
 cross=((xx-left[0])*(right[1]-left[1])-(yy-left[1])*(right[0]-left[0]))/np.linalg.norm(right-left)
 # Blend only the tiny wrist join; do not blur any other source pixels.
 weight=mask*np.clip((cross+1.5)/3,0,1)
 old=np.asarray(before).astype(np.float32)/255;old_premult=old.copy();old_premult[:,:,:3]*=old[:,:,3:4]
 mixed=old_premult*(1-weight[:,:,None])+rgba*weight[:,:,None]
 mixed[:,:,:3]/=np.maximum(mixed[:,:,3:4],1/255)
 result=np.clip(np.rint(mixed*255),0,255).astype('uint8')
 result[weight==0]=np.asarray(before)[weight==0]
 return Image.fromarray(result),Image.fromarray(np.ceil(weight*255).astype('uint8'))
def main():
 OUT.mkdir(parents=True,exist_ok=True);(OUT/'.gdignore').write_text('')
 generated=Image.open(SOURCE).convert('RGB');review=Image.new('RGB',(1440,920),'#293044');draw=ImageDraw.Draw(review)
 for row,form in enumerate(TARGET_POINTS):
  folder=ROOT/'art/characters/nezuko'/('awakening' if form=='awakening' else '')
  manifest=read(folder/'atlas.json')
  if form=='normal' and any(e['texture']=='guard-low-redraw.png' for e in manifest['clips']['guard_low']['frames']):
   print('Normal guard uses the complete v3 redraw; leaving it unchanged.');continue
  clip=read(BASE/form/'clip.json');page=Image.new('RGBA',(1024,512));entries=[];records=[]
  for i,entry in enumerate(clip['frames']):
   before=Image.open(BASE/form/f'{i}.png').convert('RGBA')
   # Share the accepted, anatomically coherent generated fists across forms.
   source_size=Image.open(BASE/'awakening'/f'{i}.png').size;x=i%3*512+24;y=i//3*512+40
   donor=unkey(generated.crop((x,y,x+source_size[0]*2,y+source_size[1]*2)))
   after,mask=patch(before,donor,SOURCE_POINTS[i],TARGET_POINTS[form][i],POLYGONS[form][i])
   frame_dir=OUT/'frames'/form;frame_dir.mkdir(parents=True,exist_ok=True);after.save(frame_dir/f'{i}.png');mask.save(frame_dir/f'{i}-mask.png')
   x=i%4*256+2;y=i//4*256+2;page.paste(after,(x,y));entries.append(dict(texture='guard-fist.png',region=[x,y,*after.size],offset=entry['offset']))
   changed=np.any(np.asarray(before)!=np.asarray(after),axis=2)
   records.append(dict(frame=i,polygon=POLYGONS[form][i],source_points=SOURCE_POINTS[i],target_points=TARGET_POINTS[form][i],changed_pixels=int(changed.sum()),source_sha256=sha(BASE/form/f'{i}.png'),mask_sha256=sha(frame_dir/f'{i}-mask.png'),result_sha256=sha(frame_dir/f'{i}.png')))
   cx,cy=TARGET_POINTS[form][i][2];box=(int(cx)-23,int(cy)-9,int(cx)+22,int(cy)+36)
   for side,im in enumerate([before,after]):
    tile=im.crop(box).resize((120,120),Image.Resampling.NEAREST);px=i*240+side*120;py=row*460+30
    review.paste(tile,(px,py),tile);draw.text((px+3,py-18),f'{form} {i} '+('original' if side==0 else 'fixed'),fill='white')
   review.paste(after,(i*240+8,row*460+195),after)
  page.save(folder/'guard-fist.png');manifest['clips']['guard_low']['frames']=entries;save(folder/'atlas.json',manifest)
  save(OUT/f'{form}-patches.json',dict(method='CPA fist anatomy; affine hand registration; local premultiplied-alpha composite',generated_source=SOURCE.relative_to(ROOT).as_posix(),generated_sha256=sha(SOURCE),frames=records))
 review.save(OUT/'review.png');print('Imported 12 hand patches; original body pixels, frame sizes, offsets and timing preserved.')
if __name__=='__main__':main()
