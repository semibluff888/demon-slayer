"""Import the four user-supplied title cards, or rebuild them offline from saved originals."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output/user-assets/battle-ui"
TARGET = ROOT / "art/ui/super-titles"
TITLES = {
    "water_dragon": "水之呼吸·拾之型·生生流转.png",
    "sun_arc": "日之呼吸·火之神神乐·碧罗之天.png",
    "sixfold": "雷之呼吸·壹之型·霹雳一闪·六连.png",
    "godspeed": "雷之呼吸·壹之型·霹雳一闪·神速.png",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(import_from=None):
    (SOURCE / "raw").mkdir(parents=True, exist_ok=True)
    TARGET.mkdir(parents=True, exist_ok=True)
    records = []
    for key, original_name in TITLES.items():
        source = SOURCE / "raw" / (key + ".png")
        if import_from is not None:
            incoming = import_from / original_name
            if not incoming.is_file():
                raise FileNotFoundError(incoming)
            shutil.copyfile(incoming, source)
        with Image.open(source) as image:
            image = image.convert("RGBA")
            bounds = image.getchannel("A").point(lambda a: 255 if a > 1 else 0).getbbox()
            if bounds is None:
                raise ValueError(f"Empty title image: {source}")
            x0, y0, x1, y1 = bounds
            crop = [max(0, x0 - 8), max(0, y0 - 8), min(image.width, x1 + 8), min(image.height, y1 + 8)]
            final = image.crop(crop)
            target = TARGET / (key + ".png")
            final.save(target, optimize=True)
            records.append(dict(
                key=key, original_filename=original_name, source=source.relative_to(ROOT).as_posix(),
                source_sha256=digest(source), source_size=list(image.size), crop=crop,
                output=target.relative_to(ROOT).as_posix(), output_size=list(final.size),
                output_sha256=digest(target)))
    manifest = dict(origin="user-supplied", processing="RGBA crop only; alpha > 1 bounds with 8px padding; no resampling or recoloring", records=records)
    (SOURCE / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(records)} transparent super titles.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--import-from", type=Path, help="Directory containing the user's original filenames; omit for offline rebuild.")
    build(parser.parse_args().import_from)
