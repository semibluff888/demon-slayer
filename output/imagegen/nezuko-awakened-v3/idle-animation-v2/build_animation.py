"""Build and check a planted-foot idle from the approved artwork; no atlas install."""
import hashlib
import json
import math
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ANIM = Path(__file__).resolve().parent
OUT = ANIM.parent
ROOT = ANIM.parents[3]
sys.path.insert(0, str(ROOT/'tools/art_v3'))
from idle_warp import mls_rigid

FONT = 'C:/Windows/Fonts/msyh.ttc'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def smooth(values):
    v = np.clip(values, 0, 1)
    return v*v*(3-2*v)


class Animator:
    def __init__(self, key, rig):
        self.key = key
        self.rig = rig
        h, w = key.shape[:2]
        self.origin = np.array(rig['source_origin'],np.float64)
        self.names = list(rig['points'])
        self.base = np.array([rig['points'][n] for n in self.names], np.float64)+self.origin
        self.yy, self.xx = np.mgrid[:h,:w].astype(np.float32)
        step = rig['grid']
        gx, gy = np.meshgrid(np.arange(0,w+step,step),np.arange(0,h+step,step))
        self.coarse_shape = gy.shape
        self.grid = np.stack([gx.ravel(),gy.ravel()],axis=1).astype(np.float64)
        self.sample_x, self.sample_y = self.xx/step, self.yy/step
        head = np.zeros((h,w),np.uint8)
        polygon = np.array(rig['rigid_head_polygon'],np.int32)+self.origin.astype(np.int32)
        cv2.fillPoly(head,[polygon],255)
        self.head = cv2.GaussianBlur(head.astype(np.float32)/255,(0,0),6)
        self.head[self.head>.999] = 1
        lock = rig['foot_lock']
        self.foot = smooth((self.yy-self.origin[1]-lock['fade_start_y'])/(lock['fully_fixed_y']-lock['fade_start_y']))
        self.fixed = self.yy >= self.origin[1]+lock['fully_fixed_y']
        self.leg = np.zeros((h,w),np.float32)
        stability = rig['lower_leg_stability']
        for region in stability['regions']:
            shape = np.zeros((h,w),np.uint8)
            polygon = np.array(region['polygon'],np.int32)+self.origin.astype(np.int32)
            cv2.fillPoly(shape,[polygon],1)
            outside = cv2.distanceTransform(1-shape,cv2.DIST_L2,5)
            weight = 1-smooth((outside-stability['outline_padding_px'])/stability['outer_feather_px'])
            begin,end = region['blend_y']
            weight *= smooth((self.yy-self.origin[1]-begin)/(end-begin))
            self.leg = np.maximum(self.leg,weight)
        self.leg_core = cv2.erode((self.leg>.9999).astype(np.uint8),np.ones((5,5),np.uint8))>0
        self.leg_core &= key[:,:,3]>128
        Image.fromarray(np.round(self.leg*255).astype(np.uint8)).save(ANIM/'lower-leg-stability-mask.png')
        self.premul = key.astype(np.float32)/255
        self.premul[:,:,:3] *= self.premul[:,:,3:4]

    def positions(self, t):
        moved = self.base.copy()
        for motion in self.rig['motions']:
            phase = motion.get('phase',0)
            wave = math.sin(2*math.pi*(t+phase))-math.sin(2*math.pi*phase)
            for name, amplitude in motion['points'].items():
                moved[self.names.index(name)] += np.array(amplitude)*wave
        return moved

    def frame(self, t, stabilize_legs=True):
        moved = self.positions(t)
        head_indices = [self.names.index(n) for n in self.rig['head_points']]
        head_displacements = moved[head_indices]-self.base[head_indices]
        assert np.max(np.abs(head_displacements-head_displacements[0])) < 1e-8
        head_delta = head_displacements[0]
        info = dict(phase=t,head_translation_px=head_delta.round(5).tolist(),head_control_scale_change=0.0)
        if np.max(np.abs(moved-self.base)) < 1e-8:
            info.update(minimum_inverse_map_jacobian=1.0,rigid_head_mapping_error_px=0.0)
            return self.key.copy(), info
        source_positions = mls_rigid(self.grid,moved,self.base,alpha=self.rig['alpha'])
        displacement = source_positions-self.grid
        # Interpolate displacement at the actual grid coordinates. Resizing an
        # absolute coordinate map would offset even a stationary drawing.
        dx = cv2.remap(displacement[:,0].reshape(self.coarse_shape).astype(np.float32),self.sample_x,self.sample_y,
                       cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
        dy = cv2.remap(displacement[:,1].reshape(self.coarse_shape).astype(np.float32),self.sample_x,self.sample_y,
                       cv2.INTER_LINEAR,borderMode=cv2.BORDER_REPLICATE)
        map_x, map_y = self.xx+dx, self.yy+dy
        head = cv2.warpAffine(self.head,np.array([[1,0,head_delta[0]],[0,1,head_delta[1]]],np.float32),
                              (self.key.shape[1],self.key.shape[0]),flags=cv2.INTER_LINEAR)
        head[head>.999] = 1
        map_x = map_x*(1-head)+(self.xx-head_delta[0])*head
        map_y = map_y*(1-head)+(self.yy-head_delta[1])*head
        core = (head == 1)&(self.key[:,:,3]>128)
        error = max(np.max(np.abs((map_x-self.xx+head_delta[0])[core])),np.max(np.abs((map_y-self.yy+head_delta[1])[core])))
        map_x = map_x*(1-self.foot)+self.xx*self.foot
        map_y = map_y*(1-self.foot)+self.yy*self.foot
        # The original MLS field also pulled on legs through neighbouring cloth
        # controls. Keep the v1 field everywhere else, but stabilize these two
        # anatomical regions instead of simply reducing the knee point offsets.
        previous_x_strain = np.gradient(map_x,axis=1)-1
        stability = self.rig['lower_leg_stability']
        fade_begin,fade_end = stability['translation_fade_y']
        drift = stability['vertical_translation_px']*math.sin(2*math.pi*t)
        drift *= 1-smooth((self.yy-self.origin[1]-fade_begin)/(fade_end-fade_begin))
        target_y = self.yy-drift
        active = (self.leg>0) if stabilize_legs else np.zeros_like(self.leg,dtype=bool)
        map_x = np.where(active,map_x*(1-self.leg)+self.xx*self.leg,map_x)
        map_y = np.where(active,map_y*(1-self.leg)+target_y*self.leg,map_y)
        info.update(lower_leg_horizontal_strain_before=float(np.max(np.abs(previous_x_strain[self.leg_core]))),
                    lower_leg_horizontal_strain_after=float(np.max(np.abs((np.gradient(map_x,axis=1)-1)[self.leg_core]))),
                    lower_leg_vertical_strain_after=float(np.max(np.abs((np.gradient(map_y,axis=0)-1)[self.leg_core]))),
                    lower_leg_vertical_drift_px=round(stability['vertical_translation_px']*math.sin(2*math.pi*t),5))
        out = cv2.remap(self.premul,map_x,map_y,cv2.INTER_LINEAR,borderMode=cv2.BORDER_CONSTANT)
        alpha = np.clip(out[:,:,3:4],0,1)
        out[:,:,:3] = np.where(alpha>1e-5,out[:,:,:3]/np.maximum(alpha,1e-5),0)
        out[:,:,3:4] = alpha
        result = np.round(np.clip(out,0,1)*255).astype(np.uint8)
        result[self.fixed] = self.key[self.fixed]
        x_y,x_x = np.gradient(map_x)
        y_y,y_x = np.gradient(map_y)
        jacobian = x_x*y_y-x_y*y_x
        solid = self.key[:,:,3]>200
        info.update(minimum_inverse_map_jacobian=round(float(jacobian[solid].min()),5),
                    rigid_head_mapping_error_px=round(float(error),7))
        return result,info


def preview_frame(image):
    canvas = Image.new('RGBA',(720,960),'#eee9e3')
    draw = ImageDraw.Draw(canvas)
    draw.text((30,20),'鬼化祢豆子 · 待机循环',font=ImageFont.truetype(FONT,28),fill='#372c30')
    draw.text((32,61),'12 帧 · 10 FPS · 1.2 秒',font=ImageFont.truetype(FONT,19),fill='#766a70')
    pic = image.resize((560,832),Image.Resampling.LANCZOS)
    canvas.alpha_composite(pic,(80,82))
    draw.text((32,921),'呼吸起伏 / 腿部稳定 / 衣发跟随',font=ImageFont.truetype(FONT,19),fill='#766a70')
    return canvas.convert('RGB')


def main():
    rig = read(ANIM/'rig.json')
    master = read(ANIM/'master.json')
    key = np.asarray(Image.open(ANIM/'idle-key.png').convert('RGBA'))
    animator = Animator(key,rig)
    for name in ['frames','game-frames','review']:
        (ANIM/name).mkdir(exist_ok=True)
    count,fps = rig['frames'],rig['fps']
    frames,metrics,previous_frames = [],[],[]
    previous_hashes = read(OUT/'records/idle-v1-pixel-baseline.json')['rgba_sha256']
    for index in range(count):
        pixels,info = animator.frame(index/count)
        assert np.array_equal(pixels[animator.fixed],key[animator.fixed]), 'Foot pixels moved'
        assert info['minimum_inverse_map_jacobian'] > 0, 'Folded mesh'
        assert info['rigid_head_mapping_error_px'] < .001, 'Head changed shape'
        assert info.get('lower_leg_horizontal_strain_after',0) < .0001, 'Calf width changed'
        previous,_ = animator.frame(index/count,stabilize_legs=False)
        assert hashlib.sha256(previous.tobytes()).hexdigest() == previous_hashes[index], 'Rebuilt v1 reference changed'
        previous_frames.append(Image.fromarray(previous))
        changed = (previous!=pixels).any(axis=2)
        assert not changed[animator.leg==0].any(), 'Approved animation changed outside the legs'
        info['changed_pixels_outside_leg_mask'] = int(changed[animator.leg==0].sum())
        image = Image.fromarray(pixels)
        path = ANIM/'frames'/('frame-%02d.png'%index)
        image.save(path)
        bounds = Image.fromarray((pixels[:,:,3]>32).astype(np.uint8)*255).getbbox()
        info.update(index=index,source=path.relative_to(ANIM).as_posix(),sha256=sha(path),bounds=list(bounds),
                    foot_pixels_changed=int((pixels[animator.fixed]!=key[animator.fixed]).any(axis=1).sum()))
        frames.append(image)
        metrics.append(info)
    assert len({r['sha256'] for r in metrics}) == count, 'Duplicate frame'
    periodic,_ = animator.frame(1)
    assert np.array_equal(periodic,np.asarray(frames[0])), 'Nonperiodic loop'

    # Game-sized frames use ONE scale and ONE translation for the whole loop.
    # The new master retains the shipped demon idle's 356 atlas-pixel height.
    target_height = 356
    scale = target_height/(master['foreground_bounds'][3]-master['foreground_bounds'][1])
    ground = np.array(rig['ground_anchor'])+np.array(rig['source_origin'])
    at = [round(448-ground[0]*scale),round(568-ground[1]*scale)]
    scaled_size = [round(key.shape[1]*scale),round(key.shape[0]*scale)]
    game_frames = []
    for index,frame in enumerate(frames):
        canvas = Image.new('RGBA',(1024,640))
        canvas.alpha_composite(frame.resize(scaled_size,Image.Resampling.LANCZOS),at)
        canvas.save(ANIM/'game-frames'/('frame-%02d.png'%index))
        game_frames.append(canvas)
    boxes = [im.getbbox() for im in game_frames]
    cell = [max(b[2]-b[0] for b in boxes)+8,max(b[3]-b[1] for b in boxes)+8]
    sheet = Image.new('RGBA',(cell[0]*4,cell[1]*3))
    packed = []
    for index,(im,b) in enumerate(zip(game_frames,boxes)):
        x,y = index%4*cell[0]+4,index//4*cell[1]+4
        crop = im.crop(b)
        sheet.alpha_composite(crop,(x,y))
        packed.append(dict(texture='idle-atlas.png',region=[x,y,crop.width,crop.height],offset=list(b[:2])))
    sheet.save(ANIM/'idle-atlas.png')
    atlas = dict(canvas_size=[1024,640],feet_anchor=[448,568],source_height=340,canonical_height=70,
                 revision='nezuko-awakened-v3-idle-review-v2',clips=dict(idle=dict(loop=True,fps=fps,cycle=True,
                 phase_breaks=[4,8],segment_sync=False,anchor_mode='feet',timeline=[],frames=packed)))
    save(ANIM/'idle-atlas.json',atlas)

    preview = [preview_frame(im) for im in frames]
    samples = Image.new('RGB',(180*4,240*3))
    for index,im in enumerate(preview):
        samples.paste(im.resize((180,240)),(index%4*180,index//4*240))
    palette = samples.quantize(colors=256,method=Image.Quantize.MEDIANCUT)
    gif = [im.quantize(palette=palette,dither=Image.Dither.NONE) for im in preview]
    gif[0].save(ANIM/'review/idle-preview.gif',save_all=True,append_images=gif[1:],duration=round(1000/fps),loop=0,disposal=2,optimize=False)
    preview[0].save(ANIM/'review/idle-preview.webp',save_all=True,append_images=preview[1:],duration=round(1000/fps),loop=0,lossless=True)
    ffmpeg = shutil.which('ffmpeg')
    if not ffmpeg:
        raise RuntimeError('ffmpeg is required for the requested playable preview')
    command = [ffmpeg,'-y','-loglevel','error','-f','rawvideo','-pixel_format','rgb24','-video_size','720x960',
               '-framerate',str(fps),'-i','pipe:0','-an','-c:v','libx264','-preset','medium','-crf','17',
               '-pix_fmt','yuv420p','-r','30','-movflags','+faststart',str(ANIM/'review/idle-preview.mp4')]
    process = subprocess.Popen(command,stdin=subprocess.PIPE,stderr=subprocess.PIPE,
                               creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    for repeat in range(4):
        for im in preview:
            process.stdin.write(im.tobytes())
    process.stdin.close()
    error = process.stderr.read().decode('utf-8',errors='replace')
    if process.wait():
        raise RuntimeError(error)

    contact = Image.new('RGB',(1600,1770),'#e9e5df')
    draw = ImageDraw.Draw(contact)
    draw.text((28,19),'鬼化祢豆子 · 12 帧待机检查',font=ImageFont.truetype(FONT,29),fill='#372c30')
    for index,frame in enumerate(frames):
        x,y=index%4*400,index//4*560+80
        draw.rounded_rectangle((x+10,y,x+390,y+545),radius=10,fill='#f5f1eb')
        pic=frame.resize((337,501),Image.Resampling.LANCZOS)
        contact.paste(pic,(x+31,y+34),pic)
        draw.text((x+23,y+9),'%02d  /  %.1f s'%(index,index/fps),font=ImageFont.truetype(FONT,18),fill='#6f626a')
    contact.save(ANIM/'review/idle-contact-sheet.png')

    arrays = [np.asarray(p,dtype=np.float32) for p in preview]
    differences = [float(np.mean(np.abs(arrays[(i+1)%count]-arrays[i]))) for i in range(count)]
    baseline = read(OUT/'runtime-baseline.json')
    runtime_changed = [name for name,digest in baseline.items() if sha(ROOT/name)!=digest]
    assert not runtime_changed, 'Runtime changed during offline animation build'
    report = dict(source=master['source'],source_sha256=master['source_sha256'],source_user_approved=True,
                  method='Same v1 MLS motion outside anatomical leg masks; lower legs use width-preserving mapping and at most 0.16 px vertical drift, blending into the thighs. Shoes stay pinned.',
                  frame_count=count,fps=fps,duration_seconds=count/fps,canvas_size=list(frames[0].size),
                  frame_zero_matches_master=bool(np.array_equal(key,np.asarray(frames[0]))),
                  cycle_endpoint_matches_frame_zero=True,unique_frames=len(set(r['sha256'] for r in metrics)),
                  all_foot_pixels_fixed=True,rigid_head_scale_change=0.0,
                  minimum_inverse_map_jacobian=min(r['minimum_inverse_map_jacobian'] for r in metrics),
                  adjacent_frame_mean_rgb_differences=differences,loop_seam_to_median_step_ratio=differences[-1]/float(np.median(differences)),
                  foreground_height_range=[min(r['bounds'][3]-r['bounds'][1] for r in metrics),max(r['bounds'][3]-r['bounds'][1] for r in metrics)],
                  game_scale=scale,game_frame_offset=at,game_feet_anchor=[448,568],target_idle_height_atlas_px=target_height,
                  target_idle_height_world_units=target_height*70/340*.85*1.15,
                  runtime_files_verified=len(baseline),runtime_files_unchanged=True,animation_user_approved=False,
                  approved_motion_outside_leg_masks_pixel_identical_to_v1=True,
                  lower_leg_horizontal_strain_before_max=max(r.get('lower_leg_horizontal_strain_before',0) for r in metrics),
                  lower_leg_horizontal_strain_after_max=max(r.get('lower_leg_horizontal_strain_after',0) for r in metrics),
                  lower_leg_vertical_strain_after_max=max(r.get('lower_leg_vertical_strain_after',0) for r in metrics),
                  frames=metrics)
    save(ANIM/'animation.json',report)
    from build_leg_comparison import main as build_leg_comparison
    build_leg_comparison(previous_frames)
    archive=ANIM/'nezuko-awakened-idle-v2-refined.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as package:
        for name in ['frames','game-frames']:
            for path in sorted((ANIM/name).glob('*.png')):
                package.write(path,path.relative_to(ANIM).as_posix())
        for name in ['approved-master-transparent.png','idle-key.png','idle-atlas.png','idle-atlas.json','rig.json','master.json','animation.json','lower-leg-stability-mask.png','calf-width-check.json','README.md']:
            package.write(ANIM/name,name)
    print(json.dumps({k:v for k,v in report.items() if k!='frames'},ensure_ascii=False,indent=2))
    print('Package:',archive)


if __name__ == '__main__':
    main()
