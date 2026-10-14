"""Checkpoint 1: prepare the v3 model sheet and idle key-pose candidate jobs.

The character-specific prompt lines (portrait notes, colours, the model-sheet pose and
the three idle candidates) come from spec/<id>.json "canon".

Writes output/imagegen/<character>-v3/jobs.json, prompts and reference copies.
Generation runs through tools/run_roster_art_job.ps1 -Manifest <jobs.json>, one
job at a time; the candidate job references the generated v3 model sheet.
"""
import argparse
import shutil

from common import ROOT, production, read, rel, save, sha256, spec

MODEL_PROMPT = """Use case: identity-preserve
Asset type: character turnaround model sheet for a 2D anime fighting game (reference art, not a sprite).
Input image 1: OLD MODEL SHEET. Costume construction reference only. Its head is too large and its legs too short; do NOT copy those proportions.
Input image 2: PORTRAIT. {portrait}.
Primary request: four full-body views of the same boy in one row, left to right: front, three-quarter view facing RIGHT, strict side profile facing RIGHT, back. Same scale, all feet on one common baseline about 60 px above the bottom edge, generous gaps between figures.
Proportions (critical): exactly {heads} heads tall. Each figure is about 900 px from the top of the hair to the sole; skull crown to chin about 138 px (spiky hair tips may rise above that). Hip joint near mid-height, long legs, normal-size hands and feet. No chibi, no big head, no stocky body.
Identity and costume: {identity}
Colours: {colours}
Pose: {model_pose}
Rendering: {style}
Constraints: no text, labels, guides, grid lines, floor, shadows or effects. Pure solid {background} background everywhere.
"""

CANDIDATE_PROMPT = """Use case: identity-preserve
Asset type: final polished 2D anime fighting-game sprite, battle idle KEY POSE candidates.
Input image 1: NEW MODEL SHEET. Exact identity, costume, colours and {heads}-head proportions.
Input image 2: PORTRAIT. {portrait} detail.
Primary request: three alternative full-body idle stances side by side in three equal columns (each column 512 px wide and the full image height), one figure per column, every figure facing RIGHT toward an off-screen opponent in three-quarter view, both feet planted on the SAME baseline 90 px above the bottom edge.
Physical ruler (identical in all three): standing upright he would measure {standing} px from the top of the hair to the sole, skull crown to chin {head} px. The stance bends the knees so each figure is about {stance_low}-{stance_high} px tall. Never enlarge the head; no chibi.
{candidates}
Identity: {identity}
Rendering: {style}
Constraints: no opponent, no effects, no water, no floor, no shadow, no text, no frame borders, no watermark. Pure solid {background} background everywhere (no gradient). Do not add the reference images as extra figures.
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', default='tanjiro')
    args = parser.parse_args()
    data = spec(args.character)
    out = production(args.character)
    for name in ('references', 'prompts', 'raw', 'records', 'imports', 'review'):
        (out / name).mkdir(parents=True, exist_ok=True)
    (out / '.gdignore').write_text('')
    sources = {
        'old-model.png': ROOT / 'output/imagegen/anime-v2/raw' / (args.character + '-model.png'),
        'portrait.png': ROOT / 'art/characters' / args.character / 'portrait.png',
    }
    references = {}
    for name, source in sources.items():
        target = out / 'references' / name
        if not target.exists():
            shutil.copyfile(source, target)
        references[name] = dict(path=rel(target), source=rel(source), sha256=sha256(target))
    ruler = data['ruler']
    canon = data['canon']
    fields = dict(heads=ruler['heads_tall'], standing=ruler['standing_px'], head=ruler['head_px'],
                  stance_low=round(ruler['standing_px'] * canon.get('stance', [0.92, 0.96])[0]),
                  stance_high=round(ruler['standing_px'] * canon.get('stance', [0.92, 0.96])[1]),
                  identity=data['identity'], style=data['style'], background=data['background_name'],
                  portrait=canon['portrait'], colours=canon['colours'], model_pose=canon['model_pose'],
                  candidates='\n'.join(canon['candidates']))
    jobs = read(out / 'jobs.json', [])
    known = {job['id'] for job in jobs}
    planned = [
        dict(id=args.character + '-v3-model', group='canon', prompt_text=MODEL_PROMPT,
             references=[references['old-model.png']['path'], references['portrait.png']['path']]),
        dict(id=args.character + '-v3-idle-candidates', group='canon', prompt_text=CANDIDATE_PROMPT,
             references=[rel(out / 'raw' / (args.character + '-v3-model.png')), references['portrait.png']['path']]),
    ]
    for job in planned:
        if job['id'] in known:
            continue
        prompt = out / 'prompts' / (job['id'] + '.txt')
        prompt.write_text(job.pop('prompt_text').format(**fields), encoding='utf-8')
        job.update(prompt=rel(prompt), out=rel(out / 'raw' / (job['id'] + '.png')), size=data['request_size'],
                   metadata=dict(character=args.character, stage='checkpoint-1'))
        jobs.append(job)
    save(out / 'jobs.json', jobs)
    save(out / 'references.json', references)
    save(out / 'authorization.json', dict(service='CPA (configured provider)', integration_authorized=True,
                                          scope=args.character + ' v3 redraw: model sheet, idle key pose, all clips',
                                          evidence='User approved docs/moveset-animation-plan.md on 2026-10-13 (full redraw with CPA).'))
    print('Prepared', len(jobs), 'jobs in', rel(out / 'jobs.json'))


if __name__ == '__main__':
    main()
