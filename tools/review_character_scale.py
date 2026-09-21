"""Review every packed character drawing beside idle at one fixed display scale.

Offline usage:
    python tools/review_character_scale.py
    python tools/review_character_scale.py --baseline artifacts/character-scale/before

The optional baseline contains CHARACTER/CLIP-00.png full-canvas frames. Comparisons
use the same canvas crop and scale; they never fit individual silhouettes.
"""
import argparse
import html
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
CELL = (380, 300)
VIEW = (148, 68, 908, 608)


def load_frames(character):
    directory = ROOT / 'art/characters' / character
    manifest = json.loads((directory / 'atlas.json').read_text(encoding='utf-8'))
    pages = {}
    clips = {}
    try:
        for clip, info in manifest['clips'].items():
            images = []
            for entry in info['frames']:
                name = entry['texture']
                if name not in pages:
                    with Image.open(directory / name) as image:
                        pages[name] = image.convert('RGBA')
                x, y, w, h = entry['region']
                frame = Image.new('RGBA', tuple(manifest['canvas_size']))
                frame.alpha_composite(pages[name].crop((x, y, x+w, y+h)), tuple(entry['offset']))
                images.append(frame)
            clips[clip] = images
    finally:
        for page in pages.values():
            page.close()
    return manifest, clips


def contact_sheet(rows, path, font):
    sheet = Image.new('RGB', (len(rows[0])*CELL[0], len(rows)*CELL[1]), '#142038')
    draw = ImageDraw.Draw(sheet)
    for r, row in enumerate(rows):
        for c, (label, frame) in enumerate(row):
            x, y = c*CELL[0], r*CELL[1]
            thumb = frame.crop(VIEW).resize((380, 270), Image.Resampling.LANCZOS)
            sheet.paste(thumb, (x, y+30), thumb)
            draw.line((x, y+280, x+379, y+280), fill='#516079')
            draw.text((x+6, y+6), label, fill='#e2ca9a', font=font)
    sheet.save(path, quality=94)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT/'artifacts/character-scale/review')
    parser.add_argument('--baseline', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype(str(ROOT/'art/fonts/NotoSansSC-ui.ttf'), 17)
    blocks = []
    for character in ('tanjiro', 'zenitsu'):
        manifest, clips = load_frames(character)
        blocks.append('<h2>'+character+'</h2>')
        for clip, images in clips.items():
            rows = []
            for start in range(0, len(images), 3):
                row = [('idle / 0', clips['idle'][0])]
                row += [(clip+' / '+str(i), images[i]) for i in range(start, min(start+3, len(images)))]
                row += [('', Image.new('RGBA', tuple(manifest['canvas_size'])))]*(4-len(row))
                rows.append(row)
            name = character+'-'+clip+'.jpg'
            contact_sheet(rows, args.output/name, font)
            blocks.append('<details><summary>'+html.escape(clip)+' / '+str(len(images))+' frames</summary><img loading="lazy" src="'+name+'"></details>')
            if args.baseline:
                baseline = args.baseline/character
                indices = sorted(set([0, *manifest['clips'][clip]['phase_breaks'], len(images)-1]))
                rows = []
                for i in indices:
                    if i >= len(images):
                        continue
                    with Image.open(baseline/(clip+'-%02d.png'%i)) as before:
                        rows.append([('idle / 0', clips['idle'][0]), ('before / '+str(i), before.convert('RGBA')), ('after / '+str(i), images[i])])
                comparison = character+'-'+clip+'-compare.jpg'
                contact_sheet(rows, args.output/comparison, font)
                blocks.append('<details><summary>'+html.escape(clip)+' / before-after</summary><img loading="lazy" src="'+comparison+'"></details>')
        print(character+': reviewed '+str(len(clips))+' clips / '+str(sum(map(len, clips.values())))+' frames')
    page = '<!doctype html><meta charset="utf-8"><title>Character scale review</title><style>body{background:#101a2b;color:#e8dfcf;font:16px system-ui;margin:32px}img{max-width:100%;display:block}summary{padding:12px;cursor:pointer}details{border-bottom:1px solid #45536d}p{max-width:900px}</style><h1>Character scale review</h1><p>Each row repeats idle at the same scale. All frames retain their feet/pelvis registration. Compare heads, torsos and limbs; crouches, rotations, swords and clothing naturally change silhouette dimensions.</p>'+''.join(blocks)
    (args.output/'index.html').write_text(page, encoding='utf-8')


if __name__ == '__main__':
    main()

