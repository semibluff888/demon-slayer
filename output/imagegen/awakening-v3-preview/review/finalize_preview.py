import json, hashlib, datetime
from pathlib import Path
from PIL import Image
root = Path('output/imagegen/awakening-v3-preview')
assets = []
for manifest in ['concepts.json', 'poses.json']:
    for job in json.loads((root / manifest).read_text('utf-8')):
        source = Path(job['out'])
        record = json.loads((root / 'records' / (job['id'] + '.json')).read_text('utf-8-sig'))
        assert record['status'] == 'generated' and source.exists()
        im = Image.open(source)
        size = list(im.size)
        im.verify()
        assets.append({'id': job['id'], 'image': job['out'], 'actual_size': size, 'prompt': job['prompt'], 'references': job['references'], 'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'preview_reviewed': True, 'user_approved': False})
status = {'status': 'awaiting_user_approval', 'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'generation': 'Authorized CPA API through existing helper and installed unmodified image_gen.py, gpt-image-2, high quality', 'integration_authorized': False, 'runtime_changes': False, 'full_animation_production_started': False, 'scope': 'Preview only: Akaza awakened portrait and Nezuko new form with six representative poses. User approval is required before replacing actual game assets.', 'pose_order': ['idle', 'crouching_guard', 'forward_kick', 'jump', 'hit_reaction', 'awakening_start'], 'preview_board': (root / 'review/character-preview.jpg').as_posix(), 'face_detail': (root / 'review/nezuko-face-detail.jpg').as_posix(), 'assets': assets, 'review_notes': ['Nezuko follows the uploaded horn, expression, facial markings, leaf vines and battle-worn outer garment; costume includes a secure crossed neckline and opaque fighting trousers.', 'Akaza retains the existing identity and tattoo geometry with illuminated eyes and stripe edges.', 'Six poses are design samples, not finalized animation frames or registered runtime atlases.']}
(root / 'preview-manifest.json').write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding='utf-8')
(root / 'review-status.json').write_text(json.dumps({'status': 'awaiting_user_approval', 'integration_authorized': False, 'manifest': 'preview-manifest.json'}, indent=2), encoding='utf-8')
print('Three generated assets inspected; awaiting user approval. Runtime files unchanged.')
