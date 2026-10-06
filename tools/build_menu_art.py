"""Install the reviewed ensemble poster from its saved CPA source. No network calls."""
from pathlib import Path
import json,hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/menu-settings-v1'
def ready():return (OUT/'raw/title-ensemble-v2.png').is_file()
def build():
 source=OUT/'raw/title-ensemble-v2.png'
 record_path=OUT/'records/title-ensemble-v2.json'
 record=json.loads(record_path.read_text(encoding='utf-8-sig'))
 if record['status']!='generated':raise ValueError('Unfinished poster request')
 image=Image.open(source).convert('RGB')
 if abs(image.width/image.height-16/9)>.02:raise ValueError('Poster must keep its authored widescreen composition')
 output=ROOT/'art/ui/title-poster.png';image.save(output)
 record.update(actual_size=list(image.size),sha256=hashlib.sha256(source.read_bytes()).hexdigest(),accepted=True,review_scope='Readable Chinese game title; twelve distinct Corps, Hashira and demon portraits; native-menu safe area; no duplicate characters.')
 record_path.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
 (OUT/'imports/title-poster.json').write_text(json.dumps(dict(source=source.relative_to(ROOT).as_posix(),output=output.relative_to(ROOT).as_posix(),actual_size=list(image.size),sha256=record['sha256'],crop=None,resampled=False),indent=2),encoding='utf-8')
 print('Installed ensemble title poster:',image.size)
if __name__=='__main__':build()
