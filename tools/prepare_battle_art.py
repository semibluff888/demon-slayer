"""Versioned battle art briefs and registered source crops; no network calls."""
import json
import shutil
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/battle-v5'
def prepare():
    for name in ('raw','prompts','records','references'):
        (OUT/name).mkdir(parents=True,exist_ok=True)
    jobs=[]
    def job(key,prompt,size,references,metadata):
        p=OUT/'prompts'/(key+'.txt')
        p.write_text(prompt+'\n',encoding='utf-8')
        jobs.append(dict(id=key,prompt=str(p.relative_to(ROOT)),out=str((OUT/'raw'/(key+'.png')).relative_to(ROOT)),size=size,references=references,metadata=metadata))
    identity={
      'tanjiro':'Tanjiro Kamado, burgundy windswept hair, red brown eyes, correct forehead scar, hanafuda earrings, green black checkered haori. Resolute, compassionate but fierce focused eyes; mature anime proportions, not chibi.',
      'zenitsu':'Zenitsu Agatsuma, short golden orange layered hair, yellow triangle-pattern haori over black uniform. Calm, eyes nearly closed in intense concentration, composed swordsman, not frightened or comic; mature anime proportions, not chibi.'}
    for cid,description in identity.items():
        job(cid+'-battle-portrait',
          'Use case: identity-preserve\nAsset: premium hand-inked anime fighting-game HUD portrait and MAX cut-in.\nReference image: exact character identity and costume.\n'+description+
          '\nDraw ONE bust portrait, three-quarter view looking slightly RIGHT toward the opponent. Head and shoulders fill the frame; ALL hair and earrings inside with 6 percent margin. Crisp expressive ink lines, layered cel shadows, luminous face, detailed hair locks, restrained moonlit blue rim light and warm skin. Torso cropped at mid-chest. Dynamic hair silhouette suitable for protruding above a frame. No sword covering the face. Flat solid pure hot magenta #ff00ff background for offline extraction, no magenta reflections or rim. No UI, text, decorative frame, effects or watermark.',
          '1024x1024',['art/characters/'+cid+'/portrait.png'],dict(kind='portrait',character=cid))
    job('water-dragon',
      'Use case: stylized-concept\nAsset: isolated anime water-dragon slash VFX texture.\nReference: match its illustrated blue water and white frothy waves. A SINGLE sinuous water dragon made entirely from deep cobalt and turquoise water, coiling from lower LEFT into a rising arc and ending in a clearly recognizable fierce dragon head facing RIGHT at 80 percent width, 45 percent height. Ink-defined jaws, water whiskers, white foam horns, bright cyan eye, tapering curved water body. No flesh or opaque scales. Strong blue body, crisp white wave crests, separated droplets, little outer glow. Full shape inside frame with 8 percent margin. Pure BLACK #000000 background, no scene, characters, words, border or watermark.',
      '1536x1024',['art/effects/water-wheel.png'],dict(kind='effect',effect='water-dragon'))
    job('sun-flame-arc',
      'Use case: stylized-concept\nAsset: isolated hand-drawn anime fighting game flame circle slash.\nONE large 300-degree counterclockwise C-shaped circular sword flame arc, open on the RIGHT, clear empty black center. Thick red and orange flame body, sharply inked flowing flame tongues following the circle, brilliant pale gold inner cutting edge, dark vermilion outer rim, detached embers. Painterly anime cel shading, elegant powerful Hinokami Kagura circular slash, rich texture not a thin neon ring. All flames inside frame with 8 percent margin. Pure BLACK #000000 background. No character, sword, scene, letters, border or watermark.',
      '1024x1024',[],dict(kind='effect',effect='sun-flame-arc'))
    layout=OUT/'references/stage-layout.png'
    if not layout.exists():shutil.copy2(ROOT/'art/stages/wisteria/panorama.png',layout)
    base=Image.open(layout).convert('RGB').resize((9600,2400),Image.Resampling.LANCZOS)
    for row,y in enumerate((0,688,1376)):
        for col in range(7):
            x=col*1344
            key=f'stage-{row}-{col}'
            ref=OUT/'references'/(key+'.png')
            base.crop((x,y,x+1536,y+1024)).save(ref)
            job(key,
              'Use case: precise-object-edit\nAsset: registered detail repaint of ONE CROP from a continuous panoramic anime fighting arena.\nThe input is the EXACT edit target. Redraw this SAME crop with beautifully crisp native-resolution hand-painted anime detail. Keep EVERY object, silhouette, roof edge, branch, mountain, shoreline, moon, reflection, paving joint and perspective at EXACTLY the same position and size. Do not invent a new composition. Maintain the same deep indigo night palette, purple wisteria and small warm amber lights; equal overall brightness. Restore clear fine ink contours and rich non-repeating natural surface detail WITHIN the existing shapes: slate grain, roof tiles, wood beams, petals, foliage and rippling water where these exist. Clean sharp artwork without photographic noise or sharpening halos. Edges continue the supplied image exactly because this crop overlaps neighboring crops. No new moon, temple, lamps, objects or reflections. No people, UI, text, grid, panel border or watermark. Full-bleed opaque painting. Output the same 3:2 crop without zooming, stretching or adding margins.',
              '1536x1024',[str(ref.relative_to(ROOT))],dict(kind='stage',rect=[x,y,1536,1024],row=row,column=col))
    (OUT/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Prepared',len(jobs),'versioned jobs; no API requests made.')
if __name__=='__main__': prepare()

