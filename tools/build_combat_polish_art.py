"""Offline rebuild of the approved water animation, independent wave and launch spray."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image
import process_anime_art as pipeline
from build_battle_art import matte

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/anime-v2'
WHEEL = 'tanjiro-water_wheel-polish-v1'
FX = {'water-slash-projectile': (512,768), 'water-slash-spray': (768,512)}

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def frame_hashes():
    result = {}
    for cid in ('tanjiro','zenitsu'):
        folder = ROOT/'art/characters'/cid
        atlas = read(folder/'atlas.json')
        pages = {}
        for clip, info in atlas['clips'].items():
            result[cid+'/'+clip] = []
            for entry in info['frames']:
                if entry['texture'] not in pages:
                    pages[entry['texture']] = Image.open(folder/entry['texture']).convert('RGBA')
                x,y,w,h = entry['region']
                crop = pages[entry['texture']].crop((x,y,x+w,y+h))
                result[cid+'/'+clip].append(dict(sha256=hashlib.sha256(crop.tobytes()).hexdigest(),offset=entry['offset']))
    return result

def build():
    before = frame_hashes()
    jobs = {job['id']:job for job in read(OUT/'jobs.json')}
    wheel = jobs[WHEEL]
    source = ROOT/wheel['out']
    with Image.open(source) as image:
        width,height = image.size
    calibration = read(OUT/'calibration.json')
    calibration.setdefault(WHEEL, dict(
        standing_height=height/3*0.96, root_fraction=0.5,
        ground_frames=[0,1,8,9,10,11],
        pelvis={'2':[0.516,0.653], '3':[0.492,0.509], '4':[0.612,0.405],
                '5':[0.552,0.455], '6':[0.396,0.432], '7':[0.508,0.554]},
        note='Combat polish: one idle-referenced anatomical scale, measured pelvis throughout backward rotation, measured feet only on grounded drawings.'))
    save(OUT/'calibration.json',calibration)
    pipeline.animations(only='tanjiro')
    records = []
    for key, size in FX.items():
        job = jobs['fx-'+key+'-polish-v1']
        path = ROOT/job['out']
        with Image.open(path) as original:
            actual_size = list(original.size)
            rgba = matte(original, True)
        bounds = rgba.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox()
        if bounds is None:
            raise ValueError('Empty effect: '+key)
        rgba = rgba.crop(bounds)
        rgba.thumbnail((size[0]-12,size[1]-12),Image.Resampling.LANCZOS)
        body = Image.new('RGBA',size)
        body.alpha_composite(rgba,((size[0]-rgba.width)//2,(size[1]-rgba.height)//2))
        destination = ROOT/'art/effects'
        body.save(destination/(key+'-body.png'))
        glow = Image.new('RGB',size)
        glow.paste(body,mask=body.getchannel('A'))
        glow.save(destination/(key+'.png'))
        records.append(dict(id=job['id'],source=job['out'],source_sha256=sha(path),
            actual_size=actual_size,crop=list(bounds),output_size=list(size),
            body='art/effects/'+key+'-body.png',glow='art/effects/'+key+'.png',
            body_sha256=sha(destination/(key+'-body.png')),glow_sha256=sha(destination/(key+'.png'))))
    after = frame_hashes()
    untouched = [key for key in before if key!='tanjiro/water_wheel']
    assert all(before[key]==after[key] for key in untouched), 'Unrelated character drawing changed'
    manifest=dict(revision='combat-polish-v1',route='CPA / gpt-image-2 via existing image_gen.py',
        wheel=dict(source=wheel['out'],source_sha256=sha(source),actual_size=[width,height],
                   frames=12,phase_breaks=[3,8],anchor_mode='pelvis',calibration=WHEEL),
        effects=records,unchanged_clips=len(untouched),
        unchanged_drawings=sum(len(before[key]) for key in untouched),
        rebuild='.venv/Scripts/python.exe tools/build_combat_polish_art.py')
    save(ROOT/'output/imagegen/combat-polish-manifest.json',manifest)
    print('COMBAT POLISH ART:',manifest['unchanged_drawings'],'unrelated drawings unchanged; 12-frame backflip and 2 independent effects.')

if __name__=='__main__':
    build()
