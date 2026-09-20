"""Mix Godot's exported PCM using actual capture event timestamps, no external audio."""
import argparse,json,wave,math
from pathlib import Path
from array import array
ROOT=Path(__file__).resolve().parents[1]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('batch',choices=['basics','specials']);args=parser.parse_args()
 folder=ROOT/'artifacts/phase2'/args.batch;cue=json.loads((folder/'cues.json').read_text(encoding='utf-8'))
 rate=22050;mix=array('d',[0.0])*math.ceil(cue['frames']/cue['fps']*rate)
 streams={}
 for path in (folder/'audio').glob('*.wav'):
  with wave.open(str(path),'rb') as audio:
   assert audio.getframerate()==rate and audio.getsampwidth()==2
   streams[path.stem]=array('h',audio.readframes(audio.getnframes()))
 for event in cue['audio_events']:
  samples=streams[event['kind']];at=round(event['tick']*rate/60);offset=0
  gain=event['gain']*10**(-17/20)/32768
  for pause in cue.get('audio_pauses',[]):
   begin=round(pause['start_tick']*rate/60);end=round(pause['end_tick']*rate/60)
   if begin < at or begin >= at+len(samples)-offset: continue
   count=begin-at
   for n in range(count): mix[at+n]+=samples[offset+n]*gain
   offset+=count;at=end
  count=min(len(samples)-offset,len(mix)-at)
  for n in range(max(0,count)): mix[at+n]+=samples[offset+n]*gain
 peak=max(abs(x) for x in mix);assert peak<1.0,('Audio clipping',peak)
 with wave.open(str(folder/'soundtrack.wav'),'wb') as audio:
  audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(rate);audio.writeframes(array('h',(int(x*32767) for x in mix)).tobytes())
 (folder/'audio-report.json').write_text(json.dumps({'events':len(cue['audio_events']),'pause_intervals':len(cue.get('audio_pauses',[])),'peak':peak,'sample_rate':rate,'method':cue['audio_method']},indent=2),encoding='utf-8')
 print(f'Mixed {len(cue["audio_events"])} logical cues; peak {peak:.3f}, no clipping.')
if __name__=='__main__':main()
