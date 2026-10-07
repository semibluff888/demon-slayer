"""Prepare exact-pose reference sheets; requests use the existing CPA queue."""
import json, math
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/awakening-v1'
FORMS={
 'nezuko':'Nezuko Kamado in awakened demon form: exactly ONE horn on her anatomical right forehead, dark leafy vine markings on forehead, cheeks, arms and calves, fierce pink slit pupils, small fangs, NO bamboo muzzle. Keep intact modest pink kimono and dark haori, black hair with orange ends. Slightly longer athletic limb proportions, never enlarge the head. No weapons.',
 'tanjiro':'Tanjiro Kamado with his red flame-shaped Demon Slayer mark on the forehead, focused determined face. Keep the exact checkered haori, katana, hair, height and anatomy. No flames or water painted into sprites.',
 'zenitsu':'Zenitsu Agatsuma fully concentrated, eyes calmly CLOSED, determined relaxed mouth. Keep the exact yellow triangle-pattern haori, katana, yellow-orange hair, height and anatomy. No lightning painted into sprites.',
 'akaza':'Akaza with more intense golden eyes and vivid blue anatomical tattoo lines, poised martial arts stance. Preserve identity, costume, pink hair and body proportions. No ground compass or energy painted into sprites.'
}
def save(path,data):
 path.parent.mkdir(parents=True,exist_ok=True)
 path.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
def extract(directory,manifest,entry,cache):
 if entry['texture'] not in cache:cache[entry['texture']]=Image.open(directory/entry['texture']).convert('RGBA')
 x,y,w,h=entry['region'];sprite=cache[entry['texture']].crop((x,y,x+w,y+h))
 canvas=Image.new('RGBA',tuple(manifest['canvas_size']))
 canvas.alpha_composite(sprite,tuple(entry['offset']))
 return canvas
def main():
 for folder in ['references','prompts','raw','records','imports','review']:(OUT/folder).mkdir(parents=True,exist_ok=True)
 jobs=[]
 for cid in FORMS:
  directory=ROOT/'art/characters'/cid
  manifest=json.loads((directory/'atlas.json').read_text(encoding='utf-8-sig'))
  cache={}
  clips=dict(manifest['clips'])
  round_path=directory/'round-atlas.json'
  if round_path.exists():clips.update(json.loads(round_path.read_text(encoding='utf-8-sig'))['clips'])
  selected=list(clips) if cid!='akaza' else []
  selected=[clip for clip in selected if clip not in ['round_intro','round_victory','round_defeat','victory','awakened_combo']]
  selected=['awakening_start']+selected
  for clip in selected:
   is_start=clip=='awakening_start'
   meta=clips['idle'] if is_start else clips[clip]
   frames=[extract(directory,manifest,e,cache) for e in meta['frames']]
   if is_start:frames=[frames[0]]*6
   count=len(frames);cols=4;rows=max(2,math.ceil(count/cols));cell=(512,384)
   sheet=Image.new('RGB',(cols*cell[0],rows*cell[1]),'#00ffff')
   bounds=[]
   for i,frame in enumerate(frames):
    scaled=frame.resize((512,320),Image.Resampling.LANCZOS)
    sheet.paste(scaled,((i%cols)*512,(i//cols)*384+40),scaled)
    bounds.append(frame.getbbox())
   jid=cid+'-'+clip
   reference=OUT/'references'/(jid+'.png');sheet.save(reference)
   direction='Create EXACTLY 6 chronological distinct activation drawings: gather breath / tense / raise head / release power / settle / ready. Fixed feet and body scale.' if is_start else f'Edit the first reference sheet IN PLACE. EXACTLY {count} drawings. Preserve each pose, gesture, facing, feet position, cell position, sequence, weapons, clothing, action silhouette and anatomy size. Change only the awakening appearance.'
   prompt=f"""Use case: identity-preserve
Asset type: production 2D anime fighting-game sprite sheet.
Image 1 is the exact pose/layout edit target. Image 2 is the character identity reference.
{direction}
{FORMS[cid]}
Premium dark ink lines, crisp two-tone cel shading matching the reference. Keep {cols} columns and {rows} rows of equal cells, chronological row-major order; all unused cells remain completely empty CYAN.
The reference root and camera are fixed. Complete head, limbs, costume and weapon inside each cell. Never enlarge crouched, rolling or horizontal poses. No captions, labels, borders, watermark, opponents, glow, shadows or special effects.
Absolutely featureless flat CYAN #00ffff background and gutters for offline alpha extraction.
"""
   prompt_path=OUT/'prompts'/(jid+'.txt');prompt_path.write_text(prompt,encoding='utf-8')
   identity=directory/('awakened-portrait.png' if cid=='nezuko' else 'portrait.png')
   jobs.append(dict(id=jid,group='awakening',out=str((OUT/'raw'/(jid+'.png')).relative_to(ROOT)),prompt=str(prompt_path.relative_to(ROOT)),references=[str(reference.relative_to(ROOT)),str(identity.relative_to(ROOT))],size=f'{sheet.width}x{sheet.height}',model='gpt-image-2',metadata=dict(character=cid,clip=clip,count=count,columns=cols,rows=rows,cell=list(cell),original_clip=meta,source_bounds=bounds)))
 save(OUT/'jobs.json',jobs)
 print('PREPARED',len(jobs),'jobs; Nezuko',sum(j['metadata']['character']=='nezuko' for j in jobs),flush=True)
if __name__=='__main__':main()
