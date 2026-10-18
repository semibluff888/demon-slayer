"""Checkpoint 1: prepare the v3 model sheet and idle key-pose candidate jobs.

The character-specific prompt lines (portrait notes, colours, the model-sheet pose and
the three idle candidates) come from spec/<id>.json "canon". Optional "canon" keys,
with the defaults used for Tanjiro and Zenitsu: "subject" ("boy"), "model_px" (900)
and "model_head_px" (138) for the model sheet's figure, "old_model" (the anime-v2
model sheet), "element" ("water", banned from the idle candidates), "pronoun" ("he")
and "authorization" (the evidence recorded in authorization.json).

An optional "canon.demon" block adds two jobs for a character whose awakened form is
drawn rather than derived (Nezuko's 鬼化): a demon-form model sheet from the new model
sheet and the user's design references ("references"), and an edit of the three idle
candidates into that form, so both forms can be compared in the same stance.

Writes output/imagegen/<character>-v3/jobs.json, prompts and reference copies.
Generation runs through tools/run_roster_art_job.ps1 -Manifest <jobs.json>, one
job at a time; the candidate job references the generated v3 model sheet.
"""
import argparse
import shutil
from pathlib import Path

from common import ROOT, production, read, rel, save, sha256, spec

MODEL_PROMPT = """Use case: identity-preserve
Asset type: character turnaround model sheet for a 2D anime fighting game (reference art, not a sprite).
Input image 1: OLD MODEL SHEET. Costume construction reference only. Its head is too large and its legs too short; do NOT copy those proportions.
Input image 2: PORTRAIT. {portrait}.
Primary request: four full-body views of the same {subject} in one row, left to right: front, three-quarter view facing RIGHT, strict side profile facing RIGHT, back. Same scale, all feet on one common baseline about 60 px above the bottom edge, generous gaps between figures.
Proportions (critical): exactly {heads} heads tall. Each figure is about {model_px} px from the top of the hair to the sole; skull crown to chin about {model_head} px (spiky hair tips may rise above that). Hip joint near mid-height, long legs, normal-size hands and feet. No chibi, no big head, no stocky body.
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
Physical ruler (identical in all three): standing upright {pronoun} would measure {standing} px from the top of the hair to the sole, skull crown to chin {head} px. The stance bends the knees so each figure is about {stance_low}-{stance_high} px tall. Never enlarge the head; no chibi.
{candidates}
Identity: {identity}
Rendering: {style}
Constraints: no opponent, no effects, no {element}, no floor, no shadow, no text, no frame borders, no watermark. Pure solid {background} background everywhere (no gradient). Do not add the reference images as extra figures.
"""


DEMON_MODEL_PROMPT = """Use case: identity-preserve
Asset type: character turnaround model sheet for a 2D anime fighting game (reference art, not a sprite).
Input image 1: NEW MODEL SHEET of her normal form. Same girl, same four views, same layout, scale and baseline.
{reference_lines}
Primary request: the same four views as input image 1 (front, three-quarter view facing RIGHT, strict side profile facing RIGHT, back), all feet on the same baseline about 60 px above the bottom edge, now in her demon form. Follow the design references closely for every costume and body detail.
Proportions (critical): {proportions}
Identity and costume: {identity}
Colours: {colours}
Pose: {model_pose}
Rendering: {style}
Constraints: {modesty} No text, labels, guides, grid lines, floor, shadows or effects (no fire, no aura). Pure solid {background} background everywhere.
"""

DEMON_CANDIDATE_PROMPT = """Use case: image edit, identity-preserve
Asset type: final polished 2D anime fighting-game sprite, battle idle KEY POSE candidates.
Input image 1: THREE IDLE STANCE CANDIDATES of her normal form, one per 512 px column. Keep each column's stance, limbs, facing (RIGHT), placement in its column and both feet on the same baseline exactly.
Input image 2: DEMON FORM MODEL SHEET. Exact demon-form identity, costume, colours and proportions.
Primary request: redraw each of the three figures in her demon form. {growth}
Demon form: {identity}
Rendering: {style}
Constraints: {modesty} No opponent, no effects, no fire, no aura, no floor, no shadow, no text, no frame borders, no watermark. Pure solid {background} background everywhere (no gradient). Do not add the reference images as extra figures.
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
    canon = data['canon']
    sources = {
        'old-model.png': ROOT / canon.get('old_model', 'output/imagegen/anime-v2/raw/%s-model.png' % args.character),
        'portrait.png': ROOT / 'art/characters' / args.character / 'portrait.png',
    }
    references = {}
    for name, source in sources.items():
        target = out / 'references' / name
        if not target.exists():
            shutil.copyfile(source, target)
        references[name] = dict(path=rel(target), source=rel(source), sha256=sha256(target))
    ruler = data['ruler']
    fields = dict(heads=ruler['heads_tall'], standing=ruler['standing_px'], head=ruler['head_px'],
                  subject=canon.get('subject', 'boy'), model_px=canon.get('model_px', 900), model_head=canon.get('model_head_px', 138),
                  element=canon.get('element', 'water'),
                  stance_low=round(ruler['standing_px'] * canon.get('stance', [0.92, 0.96])[0]),
                  stance_high=round(ruler['standing_px'] * canon.get('stance', [0.92, 0.96])[1]),
                  pronoun=canon.get('pronoun', 'he'),
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
    demon = canon.get('demon')
    if demon:
        demon_refs = []
        for n, source in enumerate(demon['references']):
            target = out / 'references' / ('demon-reference-%d.png' % (n + 1))
            if not target.exists():
                shutil.copyfile(ROOT / source if not Path(source).is_absolute() else Path(source), target)
            references[target.name] = dict(path=rel(target), source=str(source), sha256=sha256(target))
            demon_refs.append(rel(target))
        demon_fields = dict(fields, identity=demon['identity'], colours=demon['colours'], proportions=demon['proportions'],
                            model_pose=demon.get('model_pose', fields['model_pose']),
                            modesty=demon['modesty'], growth=demon['growth'],
                            reference_lines='\n'.join('Input image %d: DEMON FORM DESIGN REFERENCE %d (user supplied). %s' % (n + 2, n + 1, demon['reference_note'])
                                                      for n in range(len(demon_refs))))
        model_out = rel(out / 'raw' / (args.character + '-v3-model.png'))
        demon_model_out = rel(out / 'raw' / (args.character + '-v3-demon-model.png'))
        planned += [
            dict(id=args.character + '-v3-demon-model', group='canon', prompt_text=DEMON_MODEL_PROMPT, fields=demon_fields,
                 references=[model_out] + demon_refs),
            dict(id=args.character + '-v3-demon-candidates', group='canon', prompt_text=DEMON_CANDIDATE_PROMPT, fields=demon_fields,
                 references=[rel(out / 'raw' / (args.character + '-v3-idle-candidates.png')), demon_model_out]),
        ]
    for job in planned:
        if job['id'] in known:
            continue
        prompt = out / 'prompts' / (job['id'] + '.txt')
        prompt.write_text(job.pop('prompt_text').format(**job.pop('fields', fields)), encoding='utf-8')
        job.update(prompt=rel(prompt), out=rel(out / 'raw' / (job['id'] + '.png')), size=data['request_size'],
                   metadata=dict(character=args.character, stage='checkpoint-1'))
        jobs.append(job)
    save(out / 'jobs.json', jobs)
    save(out / 'references.json', references)
    save(out / 'authorization.json', dict(service='CPA (configured provider)', integration_authorized=True,
                                          scope=args.character + ' v3 redraw: model sheet, idle key pose, all clips',
                                          evidence=canon.get('authorization', 'User approved docs/moveset-animation-plan.md on 2026-10-13 (full redraw with CPA).')))
    print('Prepared', len(jobs), 'jobs in', rel(out / 'jobs.json'))


if __name__ == '__main__':
    main()
