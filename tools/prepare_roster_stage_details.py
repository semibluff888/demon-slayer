"""Register detail crops from existing masters. Offline and idempotent."""
import json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/roster-v1'
def main():
 jobs=json.loads((OUT/'jobs.json').read_text(encoding='utf-8-sig'))
 known={j['id'] for j in jobs}
 for master in list(jobs):
  if master['group']!='foundation' or 'stage' not in master['metadata']:continue
  sid=master['metadata']['stage'];source=ROOT/master['out']
  if not source.exists():raise SystemExit('Generate and accept stage master first: '+str(source))
  src=Image.open(source).convert('RGB');height=round(src.width/4);top=(src.height-height)//2
  panorama=src.crop((0,top,src.width,top+height)).resize((6144,1536),Image.Resampling.LANCZOS)
  for row,y in enumerate([0,512]):
   for col,x in enumerate([0,1152,2304,3456,4608]):
    jid=f'{sid}-detail-{row}-{col}'
    reference=OUT/'references'/(jid+'.png');reference.parent.mkdir(parents=True,exist_ok=True)
    if not reference.exists():panorama.crop((x,y,x+1536,y+1024)).save(reference)
    if jid in known:continue
    prompt=OUT/'prompts'/(jid+'.txt')
    prompt.write_text("""Use case: stylized-concept. Asset: detailed panorama patch.
Input is the exact composition reference for this crop of a continuous fighting stage.
Repaint precisely the same architecture, floor, lighting and colors, adding crisp painted anime detail.
Lock every beam, lantern, perspective line and horizon at its exact reference position.
Do not reframe, shift, zoom, alter geometry or invent objects. Preserve all four edges.
No people, text, logos, foreground obstacles or vignette. Output only this complete patch.
""",encoding='utf-8')
    jobs.append(dict(id=jid,group='stage-detail',prompt=prompt.relative_to(ROOT).as_posix(),
     out=(OUT/'raw'/(jid+'.png')).relative_to(ROOT).as_posix(),size='1536x1024',
     references=[reference.relative_to(ROOT).as_posix()],metadata=dict(stage=sid,target_rect=[x,y,1536,1024])))
    known.add(jid)
 (OUT/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2),encoding='utf-8')
 print('Stage detail references and manifest ready; no API requests sent.')
if __name__=='__main__':main()
