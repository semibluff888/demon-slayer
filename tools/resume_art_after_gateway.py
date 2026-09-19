"""Explicitly reviewed replacement jobs after synchronous CPA 504 responses.

The prior requests returned no image or retrievable status identifier. Their cost
remains unknown; old records remain intact, and no automatic retry loop is used.
"""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/imagegen/anime-v2'
jobs = json.loads((OUT / 'jobs.json').read_text(encoding='utf-8'))
for name in ['tanjiro-crouch_heavy', 'zenitsu-crouch_light']:
    old = next(j for j in jobs if j['id'] == name)
    if (ROOT / old['out']).exists():
        raise RuntimeError('Output exists; inspect it instead of requesting replacement')
    revised = dict(old)
    revised['id'] = name + '-r1'
    if any(j['id'] == revised['id'] for j in jobs):
        continue
    revised['out'] = 'output/imagegen/anime-v2/raw/' + revised['id'] + '.png'
    revised['metadata'] = dict(old['metadata'], replaces=name, reason='Synchronous 504 with no image or status identifier; manually reviewed after requests ended')
    old['group'] = 'failed-attempts'
    jobs.insert(jobs.index(old)+1, revised)
(OUT / 'jobs.json').write_text(json.dumps(jobs, ensure_ascii=False, indent=2), encoding='utf-8')
print('Reviewed failed requests; originals retained with unknown billing status')
