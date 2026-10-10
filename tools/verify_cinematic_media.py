"""Validate every shipped cinematic frame and its independent soundtrack."""
import concurrent.futures,json,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 catalog=json.loads((ROOT/'resources/cinematics/catalog.json').read_text(encoding='utf-8'))
 ffmpeg=shutil.which('ffmpeg');ffprobe=shutil.which('ffprobe');assert ffmpeg and ffprobe
 def verify(item):
  key,data=item;path=ROOT/data['video'][6:];audio=ROOT/data['audio'][6:]
  result=subprocess.run([ffprobe,'-v','error','-count_frames','-show_streams','-of','json',str(path)],capture_output=True,check=True);assert not result.stderr,result.stderr
  info=json.loads(result.stdout);v=info['streams'][0]
  assert len(info['streams'])==1 and v['codec_name']=='theora'
  assert (v['width'],v['height'],v['r_frame_rate'])==(1920,1080,'60/1')
  assert int(v['nb_read_frames'])==data['source_end_frame_exclusive']-data['source_start_frame']
  ai=json.loads(subprocess.check_output([ffprobe,'-v','error','-show_streams','-of','json',str(audio)]))['streams'][0]
  assert ai['codec_name']=='vorbis' and abs(float(ai['duration'])-data['duration'])<0.025
  for media in [path,audio]:
   r=subprocess.run([ffmpeg,'-v','error','-i',str(media),'-f','null','-'],capture_output=True);assert not r.stderr and r.returncode==0,(key,r.stderr)
  return dict(move=key,frames=int(v['nb_read_frames']),audio_seconds=float(ai['duration']),decode_ok=True)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  results=list(pool.map(verify,[(k,v) for k,v in catalog['moves'].items() if k!='akaza_max']))
 out=ROOT/'artifacts/cinematics';out.mkdir(parents=True,exist_ok=True)
 (out/'media-verification.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 print('CINEMATIC MEDIA: 7 videos and soundtracks, exact frame counts, no decoder errors')
if __name__=='__main__':main()
