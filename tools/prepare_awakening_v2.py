"""Prepare larger pose references with a reviewed model identity per character."""
import json,math
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/awakening-v2'
FORMS={
 'tanjiro':'Tanjiro: refined flame-shaped red forehead mark, determined red-brown eyes, composed CLOSED mouth. Same green-black checker haori, earrings, black-burgundy hair, katana. Same normal stature.',
 'zenitsu':'Zenitsu: both eyes gently CLOSED in concentration, calm small CLOSED mouth, precise golden-orange hair layers, amber triangle-pattern haori. Same normal stature.',
 'nezuko':'Nezuko: exactly ONE slender ivory horn on anatomical RIGHT forehead, about one-third head-height, fine dark crimson ivy marks on temple/cheek and exposed arms/legs. Refined pink slit pupils, CLOSED composed mouth (no scream), absolutely NO bamboo or muzzle or red strap. Intact modest pink hemp-leaf kimono, cocoa haori, obi and sandals. Long black hair with copper-orange ends. Elegant athletic limbs, slightly smaller head, intact coverage. She already has awakening anatomy in EVERY frame, even crouching, upside-down, receiving hits and falling. No extra horn.'
}
def main():
 jobs=[]
 for cid,form in FORMS.items():
  directory=ROOT/'art/characters'/cid
  manifest=json.loads((directory/'atlas.json').read_text('utf-8-sig'))
  cache={};clips=manifest['clips']
  selected=['awakening_start']+[c for c in clips if c not in ['victory','round_intro','round_victory','round_defeat']]
  for clip in selected:
   is_start=clip=='awakening_start'
   meta=clips['idle'] if is_start else clips[clip]
   entries=[meta['frames'][0]]*6 if is_start else meta['frames']
   count=len(entries);cols=3 if count<=9 else 4;rows=math.ceil(count/cols)
   cell=704 if count<=12 else 576
   sheet=Image.new('RGB',(cols*cell,rows*cell),'#00ffff');bounds=[]
   maxw=max(e['region'][2] for e in entries);maxh=max(e['region'][3] for e in entries)
   scale=(cell-112)/max(maxw,maxh)
   for i,e in enumerate(entries):
    if e['texture'] not in cache:cache[e['texture']]=Image.open(directory/e['texture']).convert('RGBA')
    x,y,w,h=e['region'];sprite=cache[e['texture']].crop((x,y,x+w,y+h))
    sprite=sprite.resize((round(w*scale),round(h*scale)),Image.Resampling.LANCZOS)
    sheet.paste(sprite,((i%cols)*cell+(cell-sprite.width)//2,(i//cols)*cell+(cell-sprite.height)//2),sprite)
    ox,oy=e['offset'];bounds.append([ox,oy,ox+w,oy+h])
   jid=cid+'-'+clip
   ref=OUT/'references'/(jid+'.png');sheet.save(ref)
   direction=('Draw EXACTLY 6 distinct activation frames: gather breath, tense, lift chin, release power, settle, ready. Preserve the reference feet and stance scale; subtle sophisticated performance, never shouting.' if is_start else f'Redraw EXACTLY {count} corresponding chronological poses from Image 1 in the polished style and identity of Image 2. Copy each original gesture, sword angle, silhouette, orientation and action precisely. Do not substitute a standing pose for an attack, crouch, jump or roll.')
   prompt=f'''Use case: style-transfer
Asset type: final high-quality 2D anime fighting-game animation sprite sheet, {clip}.
Image 1: exact action/layout reference; its drawing quality is NOT the target.
Image 2: approved final awakening model, face, costume and rendering style. This is the identity master.
{direction}
{form}
The clean delicate linework, coherent cel shading, elegant facial anatomy, proportions and rich costume colors must match Image 2. Exquisite hands, crisp hair locks and accurate costume construction. No chibi head, distorted body, screaming mouth, blurry edges or harsh flat sticker outline.
Layout: {cols} equal columns by {rows} equal rows, row-major order, EXACTLY {count} complete isolated figures. Keep every drawing centered in its own cell, consistent anatomical scale across the entire sheet, generous clean space between figures. Preserve each pose relative size as in Image 1; never enlarge a crouching or horizontal figure to fill the cell. Entire hair, horn, limbs and weapon visible with margins. Leave any unused cells empty.
Every drawing must keep the approved face even in hit reactions and upside-down poses. Nezuko never has bamboo; Zenitsu keeps closed eyes.
Absolutely flat CYAN #00ffff background including gutters, or genuine transparent alpha. No shadows, floor, glow, energy, aura, lightning, text, labels, numbers, grid lines, borders, watermarks or extra objects. Visual effects are separate.
'''
   pp=OUT/'prompts'/(jid+'.txt');pp.write_text(prompt,encoding='utf-8')
   jobs.append(dict(id=jid,group='pilot-actions' if clip in ['idle','awakening_start'] else 'awakening',out=(OUT/'raw'/(jid+'.png')).relative_to(ROOT).as_posix(),prompt=pp.relative_to(ROOT).as_posix(),references=[ref.relative_to(ROOT).as_posix(),(OUT/'raw'/(cid+'-model.png')).relative_to(ROOT).as_posix()],size=f'{sheet.width}x{sheet.height}',model='gpt-image-2',metadata=dict(character=cid,clip=clip,count=count,columns=cols,rows=rows,cell=[cell,cell],original_clip=meta,source_bounds=bounds)))
 (OUT/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2),encoding='utf-8')
 print('Prepared',len(jobs),'sheets')
if __name__=='__main__':main()
