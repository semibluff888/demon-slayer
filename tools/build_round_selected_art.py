"""Offline import of selected round actors; separate production atlas, no demo dependency."""
import hashlib,json,shutil,sys
from pathlib import Path
from PIL import Image,ImageDraw
import process_anime_art as art
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/round-selected'
SELECTION={'tanjiro':{'round_intro':'tanjiro-c-intro-v1','round_victory':'tanjiro-a-victory-v1','round_defeat':'tanjiro-defeat-v2'},'zenitsu':{'round_intro':'zenitsu-d-intro-v1','round_victory':'zenitsu-d-victory-v1','round_defeat':'zenitsu-defeat-v2'}}

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,data):art.save_json(p,data)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def idle(cid):
    folder=ROOT/'art/characters'/cid;manifest=read(folder/'atlas.json');e=manifest['clips']['idle']['frames'][0]
    x,y,w,h=e['region'];im=Image.open(folder/e['texture']).convert('RGBA').crop((x,y,x+w,y+h))
    canvas=Image.new('RGBA',art.CANVAS);canvas.alpha_composite(im,tuple(e['offset']));return canvas

def components_with_transfers(source,count,columns,split,transfers):
    pieces=split(source,count,columns)
    canvases=[]
    for bounds,frame in pieces:
        canvas=Image.new('RGBA',source.size);canvas.alpha_composite(frame,tuple(bounds[:2]));canvases.append(canvas)
    for transfer in transfers:
        rect=tuple(transfer['source_rect'])
        canvases[transfer['from']].paste((0,0,0,0),rect)
        canvases[transfer['to']].alpha_composite(source.crop(rect),rect[:2])
    return [(canvas.getbbox(),canvas.crop(canvas.getbbox())) for canvas in canvases]

def build():
    art.OUT=OUT;art.REVIEW=OUT/'review';art.ART=OUT/'packed'
    calibration=read(OUT/'calibration.json')
    report=[]
    for cid,choices in SELECTION.items():
        clips={}
        for clip,key in choices.items():
            raw=OUT/'raw'/f'{key}.png'
            if not raw.exists():
                source=ROOT/'demo/round-presentation/raw'/f'{key}.png';shutil.copy2(source,raw)
                record=read(ROOT/'demo/round-presentation/records'/f'{key}.json')
                record.update(output=str(raw.relative_to(ROOT)),promoted_from=str(source.relative_to(ROOT)),accepted=True,selection=clip)
                save(OUT/'records'/f'{key}.json',record)
                shutil.copy2(ROOT/'demo/round-presentation/prompts'/f'{key}.txt',OUT/'prompts'/f'{key}.txt')
            count=12 if clip=='round_defeat' else 18
            meta=dict(clip=clip,count=count,columns=4 if count==12 else 6,rows=3,fps=12,loop=False,root_fraction=0.5)
            split=art.sprite_components
            transfers=calibration[key].get('component_transfers',[])
            if transfers:
                art.sprite_components=lambda source,count,columns: components_with_transfers(source,count,columns,split,transfers)
            try:
                frames=art.process_clip(dict(id=key,out=str(raw.relative_to(ROOT)),metadata=meta),calibration)
            finally:
                art.sprite_components=split
            # Preserve all detached weapon pixels with explicit source ownership crops.
            # The whole canvas retains the original 448,568 registration and 340px ruler.
            clips[clip]=dict(images=frames,meta=meta)
            record=read(OUT/'records'/f'{key}.json');record.update(actual_size=list(Image.open(raw).size),sha256=sha(raw),frame_count=count)
            save(OUT/'records'/f'{key}.json',record)
            report.append(dict(character=cid,clip=clip,source=str(raw.relative_to(ROOT)),sha256=sha(raw),count=count,calibration=calibration[key]))
        art.pack(cid,clips);art.previews(cid,clips)
        temporary=art.ART/'characters'/cid;manifest=read(temporary/'atlas.json');destination=ROOT/'art/characters'/cid
        pages=set()
        for info in manifest['clips'].values():
            for e in info['frames']:
                source=e['texture'];target=source.replace('atlas-','round-');pages.add((source,target));e['texture']=target
        for source,target in pages:shutil.copy2(temporary/source,destination/target)
        manifest['source']='output/imagegen/round-selected'
        manifest['clips']['round_defeat'].update(contact_frame=6,release_frame=7 if cid=='tanjiro' else -1,final_hold=True)
        save(destination/'round-atlas.json',manifest)
        # Every row compares real idle with the selected poses at identical output scale.
        rows=[]
        for clip,info in clips.items():
            for begin in range(0,len(info['images']),4):
                rows.append((clip,begin,[idle(cid)]+info['images'][begin:begin+4]))
        page=Image.new('RGB',(1500,len(rows)*292),'#182333');d=ImageDraw.Draw(page)
        for row,(clip,begin,frames) in enumerate(rows):
            for col,im in enumerate(frames):
                # Full shared registration; no per-thumbnail silhouette fitting.
                im=im.crop((150,130,750,640)).resize((300,255),Image.Resampling.LANCZOS)
                page.paste(im,(col*300,row*292+28),im)
                d.text((col*300+8,row*292+8),'GAME IDLE' if col==0 else f'{clip} {begin+col-1:02}',fill='white')
        page.save(OUT/'review'/f'{cid}-all-scales.jpg',quality=92)
    save(OUT/'manifest.json',dict(selection=SELECTION,clips=report,rebuild='.venv/Scripts/python.exe tools/build_round_selected_art.py',ruler={'source_height':340,'canonical_height':70,'feet_anchor':[448,568]},runtime_effects='none; Tanjiro C has no fire arc'))
    print('ROUND ART: 6 clips / 96 selected drawings; unchanged base atlases; production-only paths.')
if __name__=='__main__':build()