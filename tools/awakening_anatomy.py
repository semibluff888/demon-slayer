"""Offline head-ruler registration, independent of hair/limb silhouette bounds."""
import hashlib,json,math
import cv2
import numpy as np

def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def obi_center(sprite):
    """Locate the green obi cord; costume width never controls physical size."""
    rgba=np.asarray(sprite).astype(np.int16)
    r,g,b,a=[rgba[:,:,i] for i in range(4)]
    mask=((a>180)&(g>45)&(g<195)&(g>r*1.22)&(g>b*1.18)&(g-r>12)).astype(np.uint8)
    count,labels,stats,centers=cv2.connectedComponentsWithStats(mask,8)
    if count<2:return None
    index=1+int(np.argmax(stats[1:,4]))
    if stats[index,4]<8:return None
    return centers[index].tolist()
def calibrated_frames(root,production,job):
    calibration=read(production/'anatomy-calibration.json');model=calibration['clips'].get(job['base_id'])
    if model is None:raise ValueError('Missing anatomical review: '+job['base_id'])
    digest=hashlib.sha256((root/job['out']).read_bytes()).hexdigest()
    if model['source_sha256']!=digest:raise ValueError('Anatomical review belongs to an older source: '+job['id'])
    lengths=model['head_lengths']
    if len(lengths)!=job['metadata']['count']:raise ValueError('Incomplete anatomical review: '+job['id'])
    target=float(calibration['target_head_length'])
    if not all(math.isfinite(x) and 20<x<250 for x in lengths):raise ValueError('Invalid head measurements: '+job['id'])
    return target,model

def register(sprite,index,target,model,old_sprite,old_offset,bounds):
    """Size by reviewed skull length; translate using the pose's existing waist/root."""
    length=float(model['head_lengths'][index]);scale=target/length
    old_waist=obi_center(old_sprite);new_waist=obi_center(sprite)
    if old_waist is not None and new_waist is not None:
        target_x=old_offset[0]+old_waist[0];source_x=new_waist[0];method='obi-root'
    else:
        target_x=(bounds[0]+bounds[2])/2;source_x=sprite.width/2;method='reviewed-pose-center'
    adjustment=model.get('translations',{}).get(str(index),[0,0])
    size=(max(1,round(sprite.width*scale)),max(1,round(sprite.height*scale)))
    offset=(round(target_x-source_x*scale+adjustment[0]),round(bounds[3]-size[1]+adjustment[1]))
    return scale,size,offset,dict(registration_profile='idle-head-ruler-v7',measured_head_length=length,target_head_length=target,root_method=method,source_root_x=source_x,target_root_x=target_x,translation=adjustment)
