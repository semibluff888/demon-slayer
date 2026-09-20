"""Subset bundled OFL fonts to the project's UI repertoire; no network access."""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
text = ''.join(chr(i) for i in range(32, 127)) + '滅対水雷壹贰→←↑↓＋：·凝神拔刀胜负平局再决连击秒'
for directory in ('scripts', 'moves', 'resources'):
    for source in (ROOT / directory).rglob('*'):
        if source.suffix in ('.gd', '.tres'):
            text += source.read_text(encoding='utf-8-sig')
for name, target, weight in [('NotoSansSC', 'NotoSansSC-ui', 450), ('NotoSerifSC', 'NotoSerifSC-title', 700)]:
    font = TTFont(ROOT / 'output' / 'font-sources' / (name + '.ttf'))
    font = instantiateVariableFont(font, {'wght': weight}, inplace=True)
    options = subset.Options()
    options.name_IDs = ['*']
    worker = subset.Subsetter(options=options)
    worker.populate(text=text)
    worker.subset(font)
    destination = ROOT / 'art' / 'fonts' / (target + '.ttf')
    font.save(destination)
    print(destination.name, destination.stat().st_size, 'bytes')
