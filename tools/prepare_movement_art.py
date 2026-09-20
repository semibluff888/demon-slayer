"""Versioned movement artwork briefs; service calls stay in the existing CPA helper."""
import json
from pathlib import Path
from PIL import Image
from prepare_art_production import STYLE, IDENTITY, write_job

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/anime-v2'
CLIPS = {
 'dash_forward': (8, 4, True, 'Eight distinct consecutive phases of a fast grounded RUN to the RIGHT: lean forward, drive trailing knee, push off, stride, opposite leg contacts, gather, drive, stride. A full running cycle, NOT walking. Face right throughout. Sword sheathed, one hand near hilt. Feet on ground baseline; keep upper body height stable.'),
 'dash_back': (8, 4, True, 'Eight distinct phases of a quick defensive retreat RUN toward the LEFT while head, torso and guard keep facing RIGHT. Alternating fast backward footwork, bent knees, balanced torso; never turn away and never jump or roll. Sword sheathed.'),
 'jump_forward': (8, 4, False, 'Eight phases of one CLOCKWISE FORWARD TUCKED SOMERSAULT when facing right: 1 launch rising upright, 2 tuck knees chest and lean head forward, 3 torso horizontal head right feet left, 4 fully upside down head below pelvis, 5 tucked horizontal head left feet right, 6 unfold through diagonal, 7 extend feet beneath hips for descent, 8 upright landing anticipation. Exactly one complete forward rotation, visibly upside down in frame 4. Sword safely sheathed. Keep PELVIS centered at 50% width / 55% height in EVERY cell; do not align rotating feet to a baseline.'),
 'jump_back': (8, 4, False, 'Eight phases of one COUNTERCLOCKWISE BACKWARD TUCKED SOMERSAULT while initially facing right: 1 launch upright, 2 tuck and arch backward left, 3 torso horizontal head left feet right, 4 fully upside down head below pelvis, 5 tucked horizontal head right feet left, 6 unfold diagonal, 7 extend feet for descent, 8 upright landing anticipation facing right. Exactly one backflip, not forward. Sword sheathed. Keep PELVIS centered at 50% width / 55% height in EVERY cell; do not align rotating feet to a baseline.'),
 'throw': (6, 3, False, 'Six phases of a failed close-range GRAB, NOT a palm strike: 1 crouched ready with sword sheathed, 2 reach BOTH empty bent hands toward an opponent wrist and lapel on right, 3 hands clasp closed, 4 realize missed grasp and retract elbows, 5 recover balanced guard, 6 ready. No opponent drawn. Hands curl to grasp, not flat palms.'),
 'throw_success': (12, 4, False, 'Twelve consecutive phases of an IPPON SEOI NAGE over-shoulder BACK THROW that takes a rival initially on the RIGHT and lands them on the LEFT behind the initial stance: 1 clasp wrist and lapel right, 2 pull grasp toward chest, 3 plant foot and pivot away, 4 sink hips and turn back toward rival, 5 load rival onto shoulder bending hips, 6 shoulder drives upward, 7 rotate torso deeply and pull arms over shoulder LEFT, 8 deep forward bend with hands carrying rival down LEFT, 9 forceful pull-down left at slam, 10 release hands toward left ground, 11 rise after follow-through, 12 recover standing facing LEFT. Draw ONLY the thrower, NEVER draw opponent, ghost, mannequin, motion trails or another body. Sword sheathed. Clear bent elbows, loaded shoulder and deep waist bend, never a palm attack. Original full human body scale, no enlargement. Feet remain on common ground baseline.'),
 'thrown': (12, 4, False, 'Twelve chronological frames of the VICTIM of an over-shoulder throw. Draw ONLY this character; NEVER draw a thrower, second body, mannequin or shadow. Initially FACING LEFT: 1 wrist caught with arm reaching left, 2 pulled off balance left, 3 chest lowered toward left, 4 belly loads onto imaginary shoulder, 5 pelvis lifted and legs curl, 6 body fully horizontal belly down, 7 rotate head-down feet up, 8 upside down with back arched for fall, 9 back contacts ground head LEFT and feet RIGHT, 10 body compresses lying on back, 11 arms and legs settle, 12 remain lying flat on back. Sword safely sheathed, no blood. Preserve body size through all rotations. Center PELVIS at 50% width / 55% height in every cell, including lying poses.'),
}
def main():
 jobs = json.loads((OUT/'jobs.json').read_text(encoding='utf-8-sig'))
 existing = {j['id'] for j in jobs}
 for character in IDENTITY:
  for clip, (count, columns, loop, motion) in CLIPS.items():
   asset_id = character + '-' + clip + '-movement-v3'
   if asset_id in existing:
    continue
   rows = (count + columns - 1)//columns
   refs = [str((OUT/'raw'/(character+'-model.png')).relative_to(ROOT)),
           str((OUT/'raw'/(character+('-idle-v2.png' if character=='tanjiro' else '-idle.png'))).relative_to(ROOT))]
   prompt = ('Use case: stylized-concept\nAsset: animation sprites for the existing 2D fighting game.\n'+STYLE+'\n'+IDENTITY[character]+'\n'
    'Image 1 is identity/costume reference; image 2 is the strict HEAD, HAND and LIMB PROPORTION reference. Match its anatomy; never chibi.\n'
    'Draw EXACTLY %d separate full-body frames in an invisible regular %d-column by %d-row grid, chronological row-major order.\n'%(count,columns,rows)+
    'Requested cells are 768 x 768. Unbent standing body height is 500 pixels, head approximately 72 pixels high in EVERY cell. Crouching and rotation NEVER enlarge the head or limbs.\n'
    'Keep entire hair, hands, feet, sword and scabbard separated from neighboring cells. Do not include a drawn floor, effects, labels or grid lines. Grounded pelvis x=50%%, feet baseline y=90%%.\n'
    'Motion: '+motion+'\n'
    'Pure uniform HOT MAGENTA #ff00ff backdrop across all empty pixels, no shadows or gradients. The ONLY figures are the %d frames of this ONE character. Every pose distinct.'%count)
   write_job(jobs, asset_id, 'movement-v3', prompt, '%dx%d'%(columns*768,rows*768), refs,
     dict(character=character,clip=clip,count=count,columns=columns,rows=rows,loop=loop,fps=24 if loop else 16,
          anchor_mode='pelvis' if clip in ('jump_forward','jump_back','thrown') else 'feet',
          pelvis_fraction=[0.5,0.55], root_fraction=0.5, standing_fraction=500/768))
 # Two outpaint panels preserve the original center instead of stretching the painting.
 center = Image.open(ROOT/'art/stages/wisteria/menu.jpg').convert('RGB').resize((2048,1152))
 for side in ('left','right'):
  asset_id = 'wisteria-'+side+'-movement-v3'
  ref = OUT/'references'/(asset_id+'.png')
  ref.parent.mkdir(parents=True,exist_ok=True)
  canvas = Image.new('RGB',(1792,1152),'#101a32')
  canvas.paste(center.crop((0,0,512,1152)) if side=='left' else center.crop((1536,0,2048,1152)), (1280 if side=='left' else 0,0))
  canvas.save(ref)
  if asset_id in existing:
   continue
  prompt = ('Use case: precise-object-edit\nAsset: horizontal OUTPAINT extension for existing side-view fighting stage.\n'
   'Input image 1 is edit target: preserve its painted %smost 512-pixel strip exactly; fill ONLY the blank remaining 1280 pixels with a seamless continuation.\n'%('right' if side=='left' else 'left')+
   'Input image 2 is the full original scene for lighting, architectural scale and perspective reference. Extend its %s edge.\n'%side+
   'Continue the wet stone fighting terrace with precisely matching slab scale and a straight horizontal back edge, same horizon height, same fixed side camera. '
   'Distant Japanese garden walls, pines and modest stone lanterns, violet wisteria at top; keep the fight lane at lower 23 percent flat and unobstructed. '
   'Do NOT copy or mirror the main temple, moon or bridge. No new giant buildings, stairs on the terrace, people, UI, text, watermark. '
   'Exact matching elegant moonlit hand-painted anime style, deep indigo/violet, silver moonlight and small warm amber lights. NO stretching or reframing the preserved strip.')
  write_job(jobs,asset_id,'movement-stage-v3',prompt,'1792x1152',[str(ref.relative_to(ROOT)),'art/stages/wisteria/menu.jpg'],
    dict(stage_extension=side))
 (OUT/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('Prepared 14 character sheets and 2 stage extensions; existing records preserved.')
if __name__=='__main__':
 main()
