"""Subset bundled OFL fonts to the project's UI repertoire.

Sources live in output/font-sources/ (ignored by Git). Pass --fetch to download
missing originals from the Google Fonts repository; provenance and SHA-256 of
every source and output are written to art/fonts/fonts.json.
"""
import argparse
import hashlib
import json
import shutil
import urllib.request
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'output' / 'font-sources'
FONTS = ROOT / 'art' / 'fonts'
MIRRORS = ['https://raw.githubusercontent.com/google/fonts/main/',
           'https://cdn.jsdelivr.net/gh/google/fonts@main/']
# source file, repository path, output, wght instance (None = static), CJK repertoire
FAMILIES = [
    ('NotoSansSC.ttf', 'ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf', 'NotoSansSC-ui', 500, True),
    ('NotoSerifSC.ttf', 'ofl/notoserifsc/NotoSerifSC%5Bwght%5D.ttf', 'NotoSerifSC-title', 900, True),
    ('MaShanZheng-Regular.ttf', 'ofl/mashanzheng/MaShanZheng-Regular.ttf', 'MaShanZheng-display', None, True),
    ('Oswald.ttf', 'ofl/oswald/Oswald%5Bwght%5D.ttf', 'Oswald-numeric', 700, False),
]
LICENSES = [('MaShanZheng-OFL.txt', 'ofl/mashanzheng/OFL.txt'), ('Oswald-OFL.txt', 'ofl/oswald/OFL.txt')]
# Glyphs composed at runtime (formal numerals, round callouts, prompts and symbols).
EXTRA = ('零壹贰叁肆伍陆柒捌玖拾佰第回合胜负平局开战全集中时间到两败俱伤已分'
         '滅対水雷凝神拔刀再决连击秒→←↑↓↖↗↘↙＋：·—…「」『』●○◆◇■□▲△▼▽★☆×∞')


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch(name: str, repository_path: str) -> None:
    target = SOURCES / name
    if target.exists():
        return
    SOURCES.mkdir(parents=True, exist_ok=True)
    for mirror in MIRRORS:
        try:
            with urllib.request.urlopen(mirror + repository_path, timeout=600) as response:
                target.write_bytes(response.read())
            print('fetched', name, 'from', mirror)
            return
        except OSError as error:
            print('mirror failed', mirror, error)
    raise SystemExit('Cannot download ' + repository_path)


def repertoire() -> str:
    text = ''.join(chr(i) for i in range(32, 127)) + EXTRA
    for directory in ('scripts', 'moves', 'resources'):
        for source in (ROOT / directory).rglob('*'):
            # JSON tables carry display text too (music titles in resources/music/library.json).
            if source.suffix in ('.gd', '.tres', '.json'):
                text += source.read_text(encoding='utf-8-sig')
    return ''.join(sorted(set(text)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--fetch', action='store_true', help='download missing source fonts')
    args = parser.parse_args()
    if args.fetch:
        for name, path, *_ in FAMILIES:
            fetch(name, path)
        for name, path in LICENSES:
            fetch(name, path)
    text = repertoire()
    latin = ''.join(c for c in text if ord(c) < 0x2000)
    record = {'note': 'SIL OFL 1.1 fonts subset by tools/subset_fonts.py', 'fonts': []}
    for name, path, target, weight, cjk in FAMILIES:
        source = SOURCES / name
        font = TTFont(source)
        if weight is not None and 'fvar' in font:
            font = instantiateVariableFont(font, {'wght': weight}, inplace=True)
        options = subset.Options()
        options.name_IDs = ['*']
        worker = subset.Subsetter(options=options)
        worker.populate(text=text if cjk else latin)
        worker.subset(font)
        destination = FONTS / (target + '.ttf')
        font.save(destination)
        record['fonts'].append({'output': destination.name, 'bytes': destination.stat().st_size,
            'sha256': sha256(destination), 'source': path, 'source_sha256': sha256(source), 'weight': weight})
        print(destination.name, destination.stat().st_size, 'bytes')
    for name, _ in LICENSES:
        if (SOURCES / name).exists():
            shutil.copyfile(SOURCES / name, FONTS / name)
    (FONTS / 'fonts.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
