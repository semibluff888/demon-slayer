"""One compact overview of processed clips: one row per clip, the approved idle first,
floor line and flagged frames marked red. Written to artifacts/art-v3/<id>/overview-N.png.

Usage: python tools/art_v3/overview.py --clips a,b,c [--character tanjiro] [--rows 8]
"""
import argparse
import json

from PIL import Image, ImageDraw, ImageFont

from common import ROOT, production

CELL = (150, 104)
CROP = (130, 150, 900, 600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', default='tanjiro')
    parser.add_argument('--clips', required=True)
    parser.add_argument('--rows', type=int, default=8)
    args = parser.parse_args()
    imports = production(args.character) / 'imports'
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 13)
    idle = Image.open(imports / 'idle/frame-00.png').convert('RGBA').crop(CROP).resize(CELL, Image.Resampling.LANCZOS)
    clips = [c for c in args.clips.split(',') if c]
    folder = ROOT / 'artifacts/art-v3' / args.character
    for sheet_index in range(0, len(clips), args.rows):
        chunk = clips[sheet_index:sheet_index + args.rows]
        width = max(len(list((imports / c).glob('frame-*.png'))) for c in chunk) + 1
        sheet = Image.new('RGB', (110 + width * CELL[0], len(chunk) * CELL[1]), '#1b2233')
        draw = ImageDraw.Draw(sheet)
        for row, clip in enumerate(chunk):
            y = row * CELL[1]
            record = json.loads((imports / (clip + '.json')).read_text(encoding='utf-8'))
            draw.text((4, y + 40), clip, fill='#ffd27f', font=font)
            sheet.paste(idle, (110, y), idle)
            floor = y + int((568 - CROP[1]) * CELL[1] / (CROP[3] - CROP[1]))
            for index, path in enumerate(sorted((imports / clip).glob('frame-*.png'))):
                x = 110 + (index + 1) * CELL[0]
                frame = Image.open(path).convert('RGBA').crop(CROP).resize(CELL, Image.Resampling.LANCZOS)
                sheet.paste(frame, (x, y), frame)
                info = record['frames'][index] if index < len(record['frames']) else {}
                draw.text((x + 2, y + 1), str(index), fill='#ff6060' if info.get('flags') else '#7fd0ff', font=font)
            draw.line((110, floor, sheet.width, floor), fill='#3a4866')
        path = folder / ('overview-%d.png' % (sheet_index // args.rows))
        sheet.save(path)
        print(path.relative_to(ROOT))


if __name__ == '__main__':
    main()
