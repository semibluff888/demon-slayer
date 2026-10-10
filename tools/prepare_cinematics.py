"""Build Godot-native Theora videos from the preserved 1080p60 source."""
import argparse, concurrent.futures, json, shutil, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DATA=[
 ('tanjiro_super','01_tanjiro_water',144,787,'water_dragon',[11,12,13,14],'water',False,0.0),
 ('tanjiro_max','02_tanjiro_hinokami',2184,2903,'sun_arc',[6,7,8,9,10,11],'flame',False,35.0),
 ('nezuko_super','04_nezuko_blood',5493,6282,'blood_burst',[4,10,11],'blood',False,0.0),
 ('nezuko_max','05_nezuko_awakened',6684,7433,'awakened_combo',[9,11],'blood',False,0.0),
 ('zenitsu_super','06_zenitsu_sixfold',12366,13045,'sixfold',[14,15,16,17],'thunder',True,0.0),
 ('zenitsu_max','07_zenitsu_godspeed',13404,14114,'godspeed',[9,10,11,12,13,14],'thunder',True,30.0),
 ('akaza_super','08_akaza_ultimate',31584,32511,'annihilation',[7,8,9,10,11],'shockwave',False,0.0),
]
def main():
 p=argparse.ArgumentParser();p.add_argument('--video-only',action='store_true');p.add_argument('--source',type=Path,default=ROOT/'output/ultimate-video-review/source/original.mp4');args=p.parse_args()
 ffmpeg=shutil.which('ffmpeg'); assert ffmpeg and args.source.is_file()
 asset=ROOT/'art/cinematics'; asset.mkdir(parents=True,exist_ok=True)
 preview=ROOT/'output/ultimate-video-review/trimmed';preview.mkdir(parents=True,exist_ok=True)
 def build(row):
  move,stem,start,end,clip,frames,effect,away,height=row
  duration=(end-start)/60
  base=[ffmpeg,'-v','error','-y','-ss',f'{start/60:.9f}','-i',str(args.source),'-t',f'{duration:.9f}','-map','0:v:0','-map','0:a:0','-map_metadata','-1']
  # Separate streams avoid Ogg A/V interleaving corruption in ffmpeg/libtheora.
  subprocess.run(base+['-an','-c:v','libtheora','-q:v','7','-g','1','-pix_fmt','yuv420p',str(asset/(move+'.ogv'))],check=True)
  subprocess.run(base+['-vn','-c:a','libvorbis','-q:a','5',str(asset/(move+'.ogg'))],check=True)
  if not args.video_only:
   subprocess.run(base+['-c:v','libx264','-crf','17','-preset','medium','-threads','3','-c:a','aac','-b:a','192k','-movflags','+faststart',str(preview/(stem+'.mp4'))],check=True)
  print(f'Encoded {move}: {duration:.6f}s / {end-start} frames',flush=True)
  return move,dict(video='res://art/cinematics/'+move+'.ogv',audio='res://art/cinematics/'+move+'.ogg',duration=duration,source_start_frame=start,source_end_frame_exclusive=end,recovery_clip=clip,recovery_frames=frames,effect=effect,face_away=away,attacker_height=height,tail_seconds=1.15,recovery_seconds=0.65)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool: entries=dict(pool.map(build,DATA))
 entries['akaza_max']=dict(entries['akaza_super'])
 entries['akaza_max']['shared_with']='akaza_super'
 out=ROOT/'resources/cinematics';out.mkdir(parents=True,exist_ok=True)
 (out/'catalog.json').write_text(json.dumps(dict(source_url='https://www.youtube.com/watch?v=-cnMjZ1v4fU',fps=60,moves=entries),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('CINEMATIC ASSETS READY',flush=True)
if __name__=='__main__':main()
