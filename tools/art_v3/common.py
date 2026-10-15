"""Shared paths and helpers for the v3 character art pipeline (offline, no network)."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / 'tools'
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))
SPEC = Path(__file__).resolve().parent / 'spec'
POSES = Path(__file__).resolve().parent / 'poses'


def production(character):
    return ROOT / 'output/imagegen' / (character + '-v3')


def read(path, default=None):
    path = Path(path)
    return json.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else default


def save(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rel(path):
    return Path(path).resolve().relative_to(ROOT).as_posix()


def spec(character):
    return read(SPEC / (character + '.json'))


MAGENTA = (255, 0, 255)


def cutout(image, data=None):
    """The drawing cut out of the background named in spec/<id>.json ("background").
    Magenta (Tanjiro, Zenitsu) keeps process_anime_art.cutout exactly; any other key
    (Akaza's vest is magenta, so his sheets use green) is matted by key dominance.
    Both keep native alpha: CPA sometimes returns real alpha instead of the flat key."""
    background = tuple((data or {}).get('background', MAGENTA))
    if background == MAGENTA:
        import process_anime_art as legacy
        return legacy.cutout(image)
    return key_matte(image, background)


def key_matte(image, key):
    """Soft matte against a saturated green (or other primary) key, after
    tools/build_roster_art.matte: coverage falls as the key channel dominates the other
    two, and edge pixels are un-mixed against the sheet's own corner colour."""
    import numpy as np
    from PIL import Image
    rgba = np.asarray(image.convert('RGBA')).astype(np.float32)
    rgb = rgba[:, :, :3]
    channel = int(np.argmax(key))
    others = [c for c in range(3) if c != channel]
    dominance = rgb[:, :, channel] - np.maximum(rgb[:, :, others[0]], rgb[:, :, others[1]])
    coverage = 1.0 - np.clip((dominance - 28.0) / 75.0, 0.0, 1.0)
    corner = rgba[0, 0]
    matte = corner[:3] if corner[3] > 250 and corner[channel] - max(corner[others[0]], corner[others[1]]) > 120 else np.array(key, np.float32)
    alpha = coverage * rgba[:, :, 3] / 255.0
    clean = np.clip((rgb - matte * (1.0 - coverage[:, :, None])) / np.maximum(coverage[:, :, None], 0.001), 0, 255)
    result = np.dstack([clean, alpha * 255.0]).astype(np.uint8)
    result[alpha < 0.02] = 0
    return Image.fromarray(result, 'RGBA')
