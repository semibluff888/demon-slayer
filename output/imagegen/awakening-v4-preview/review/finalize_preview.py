from pathlib import Path
from datetime import datetime, timezone
from PIL import Image, ImageDraw, ImageFont
import hashlib, json
root = Path.cwd()
v3 = root / 'output/imagegen/awakening-v3-preview'
v4 = root / 'output/imagegen/awakening-v4-preview'
now = datetime.now(timezone.utc).isoformat()
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def save(path, data): path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def rel(path): return path.relative_to(root).as_posix()
source = v4 / 'raw/nezuko-idle-v4.png'
reference = v3 / 'references/nezuko-user-reference.png'
original_upload = Path('C:/Users/Bo/AppData/Local/Temp/codex-clipboard-a4c8f538-6012-467c-ab89-6866714318fd.png')
assert source.exists()
if original_upload.exists():
    assert sha(reference) == sha(original_upload), 'Durable reference must match actual user upload'
record = read(v4 / 'records/nezuko-idle-v4.json')
assert record['status'] == 'generated'
assert record['references'] == [rel(reference)]
image = Image.open(source)
manifest = {
    'status': 'awaiting_user_approval', 'created_at': now,
    'integration_authorized': False, 'runtime_changes': False,
    'full_animation_production_started': False,
    'generation': 'Authorized CPA API, existing helper invoking installed image_gen.py edit with one actual image attachment; gpt-image-2, quality high',
    'asset': {
        'id': 'nezuko-idle-v4', 'image': rel(source), 'actual_size': list(image.size),
        'sha256': sha(source), 'prompt': rel(v4 / 'prompts/nezuko-idle-v4.txt'),
        'references': [{'image': rel(reference), 'sha256': sha(reference), 'role': 'unchanged original user-uploaded illustration passed via --image'}],
        'generation_record': rel(v4 / 'records/nezuko-idle-v4.json'),
        'preview_reviewed': True, 'user_approved': False
    },
    'review_notes': [
        'Both arms hang naturally beside the body, open hands below the obi.',
        'No extra trousers or leggings. Asymmetric damaged kimono, bare legs and leaf-vine details follow the reference.',
        'Face, horn, hair silhouette and costume colors closely retain the actual attached source.',
        'The upper kimono overlaps across the chest without cleavage; neutral nonsexual full-body presentation.',
        'This is one design preview, not a runtime sprite or completed animation set. Nezuko runtime art is unchanged.'
    ]
}
save(v4/'preview-manifest.json', manifest)
save(v4/'review-status.json', {'status':'awaiting_user_approval','character':'nezuko','integration_authorized':False,'runtime_changes':False,'manifest':'preview-manifest.json'})
# Verify exact on-screen avatar regions across the four captured match states.
capture_dir = v3/'review/runtime'
names = ['akaza-normal','akaza-p1-awakened','akaza-expired','akaza-p2-awakened']
shots = {name: Image.open(capture_dir/(name+'.png')).convert('RGB') for name in names}
regions = [(24,14,112,102),(1168,14,1256,102)]
def avatar(name, slot): return shots[name].crop(regions[slot])
comparisons = {
    'p1_changes_during_awakening': avatar(names[0],0).tobytes() != avatar(names[1],0).tobytes(),
    'p2_stays_normal_when_only_p1_awakes': avatar(names[0],1).tobytes() == avatar(names[1],1).tobytes(),
    'p1_returns_to_original_after_expiry': avatar(names[0],0).tobytes() == avatar(names[2],0).tobytes(),
    'p2_changes_during_awakening': avatar(names[0],1).tobytes() != avatar(names[3],1).tobytes(),
    'p1_stays_normal_when_only_p2_awakes': avatar(names[0],0).tobytes() == avatar(names[3],0).tobytes()
}
assert all(comparisons.values()), comparisons
save(capture_dir/'portrait-pixel-checks.json', comparisons)
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 21)
small = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 17)
board = Image.new('RGB',(1000,520),'#111925')
draw = ImageDraw.Draw(board)
draw.text((28,18),'AKAZA / ACTUAL IN-GAME HUD',font=font,fill='#EDF2FA')
labels = ['Both normal','P1 awakened','Awakening ended','P2 awakened']
resampling = getattr(Image,'Resampling',Image)
for column,(name,label) in enumerate(zip(names,labels)):
    x = 26+column*244
    draw.text((x,58),label,font=small,fill='#90BACC')
    for slot in range(2):
        y = 100+slot*202
        draw.text((x,y-20),'P'+str(slot+1),font=small,fill='#B8C4D5')
        board.paste(avatar(name,slot).resize((176,176),resampling.LANCZOS),(x,y))
board.save(v3/'review/akaza-hud-check.png')
import_record = read(v3/'imports/akaza-portrait.json')
import_record['validation'] = {'godot_import':'passed with mipmaps','runtime_capture':'9 passed, 0 failed','pixel_checks':comparisons,'existing_presentation_tests':'30 passed, 0 failed','existing_art_tests':'5 passed','capture_report':rel(capture_dir/'captures.json')}
import_record['integrated_at'] = now
save(v3/'imports/akaza-portrait.json',import_record)
old = read(v3/'preview-manifest.json')
old.update({'status':'akaza_integrated_nezuko_revision_pending','updated_at':now,'integration_authorized':False,'integration_authorized_for':['akaza-awakening-portrait-v3'],'runtime_changes':True,'runtime_changed_characters':['akaza'],'scope':'Akaza portrait approved and integrated. Nezuko v3 designs require revision and are superseded by the v4 preview; Nezuko runtime replacement remains unauthorized.','current_nezuko_preview':rel(v4/'preview-manifest.json')})
for item in old['assets']:
    if item['id']=='akaza-awakening-portrait-v3':
        item.update({'user_approved':True,'status':'integrated','runtime_asset':'art/characters/akaza/awakening/portrait.png','import_record':rel(v3/'imports/akaza-portrait.json')})
    else:
        item.update({'user_approved':False,'status':'revision_requested','superseded_by':rel(source)})
save(v3/'preview-manifest.json',old)
save(v3/'review-status.json',{'status':'partially_approved','manifest':'preview-manifest.json','characters':{'akaza':{'user_approved':True,'integration_authorized':True,'integrated':True},'nezuko':{'user_approved':False,'integration_authorized':False,'integrated':False,'current_preview':rel(v4/'preview-manifest.json')}}})
print(json.dumps({'nezuko_size':list(image.size),'nezuko_sha256':sha(source),'reference_sha256':sha(reference),'akaza_pixel_checks':comparisons},indent=2))
