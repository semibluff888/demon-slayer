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
