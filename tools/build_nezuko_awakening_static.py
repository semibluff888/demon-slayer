"""Install the reviewed Nezuko v6 portrait and emit offline provenance."""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/awakening-v6'

def main():
    source = OUT / 'raw/nezuko-portrait.png'
    record = json.loads((OUT/'records/nezuko-portrait.json').read_text(encoding='utf-8-sig'))
    if record.get('status') != 'generated':
        raise SystemExit('Inspect uncertain portrait request before importing')
    approval = json.loads((OUT/'authorization.json').read_text(encoding='utf-8-sig'))
    if not approval.get('integration_authorized'):
        raise SystemExit('Integration has not been authorized')
    image = Image.open(source).convert('RGB')
    if image.width != image.height:
        raise SystemExit('Portrait requires a reviewed square source')
    target = ROOT/'art/characters/nezuko/awakening/portrait.png'
    image.resize((512,512),Image.Resampling.LANCZOS).save(target,optimize=True)
    result = dict(source=source.relative_to(ROOT).as_posix(),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),source_size=list(image.size),destination=target.relative_to(ROOT).as_posix(),destination_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),destination_size=[512,512],operation='Uniform Lanczos resize; full square composition preserved')
    (OUT/'imports/nezuko-static.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('Installed revised Nezuko awakened portrait')

if __name__ == '__main__':
    main()
