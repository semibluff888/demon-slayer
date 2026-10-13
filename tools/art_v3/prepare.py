"""Prepare v3 clip generation jobs from the pose scripts (tools/art_v3/poses/<id>.json).

Every sheet is 1536x1024 with one row of equal, FULL columns: "tall" clips use three
512x1024 columns, "wide" clips two 768x1024 columns. A sheet with fewer drawings
would get wider columns, and the model then draws a larger figure with different
proportions, so a short final sheet is padded with the preceding frame(s). Padded
frames overlap the previous sheet and calibrate its scale in process.py.
Parts of a clip run in order; each later part also references the previous part.

Usage: python tools/art_v3/prepare.py --clips walk,stand_light --group pilot
       python tools/art_v3/prepare.py --redo walk:2,water_slash:1 --group pilot-r1
"""
import argparse

from common import POSES, production, read, rel, save, spec

LAYOUTS = {'tall': 3, 'wide': 2}

PROMPT = """Use case: identity-preserve
Asset type: final polished 2D anime fighting-game sprite animation frames, {name} "{clip}" (frames {first}-{last} of {total}).
Input image 1: APPROVED IDLE POSE. Exact character design, proportions, scale, line weight and rendering; it is his neutral fighting stance.
Input image 2: APPROVED MODEL SHEET. Costume construction and colours.
Input image 3: PORTRAIT. Face, eyes, hair and forehead scar.
{previous}Primary request: {count} sequential full-body drawings side by side in {count} equal columns ({cell} px wide, the full 1024 px image height), left to right, one drawing per column, all facing RIGHT.
Scale (critical): every drawing uses exactly the scale of input image 1. In the guard stance of input image 1 he is 840 px tall from the top of the hair to the soles; upright he would be about 880 px; hair top to chin is 160 px. Bent knees or a lunge lower the body, but the head, torso and legs keep exactly these lengths. Never enlarge the head, never shorten the legs; no chibi. Feet touching the ground stand on one shared baseline 40 px above the bottom edge. Blades, sleeves and the haori stay inside their own column.
Katana (critical): the blade from the guard to the tip is about 350 px in every drawing, as long as in input image 1. Never shorten it; when it points across the body or straight forward, show its full length.
Motion: {intro}
{frames}
Identity: {identity}
Rendering: {style} Same line weight and colours as input image 1 in every drawing.
Constraints: no effects (no water, fire, trails or speed lines), no opponent, no floor, no shadow, no text, no grid lines, no borders, no watermark. Pure solid {background} background everywhere. Do not add the reference images as extra figures.
"""


def parts(count, columns):
    """Full chunks of `columns`; a short last chunk is padded with preceding frames.
    Returns [(drawn indices, overlap indices)]."""
    result = []
    for start in range(0, count, columns):
        chunk = list(range(start, min(count, start + columns)))
        overlap = []
        if len(chunk) < columns and start > 0:
            overlap = list(range(max(0, chunk[0] - (columns - len(chunk))), chunk[0]))
            chunk = overlap + chunk
        result.append((chunk, overlap))
    return result


def make_job(args, data, pose, clip, index, chunk, overlap, previous_out, revision=''):
    out = production(args.character)
    frames = pose['frames']
    job_id = '%s-v3-%s-p%d%s' % (args.character, clip, index, revision)
    count = len(chunk)
    cell = 1536 // count
    lines = []
    for n, i in enumerate(chunk):
        repeat = ' (repeats frame %d of input image 4 exactly; it aligns the two sheets)' % (n + 1 + count - len(overlap)) if i in overlap else ''
        lines.append('Frame %d: %s%s' % (n + 1, frames[i], repeat))
    previous = ('Input image 4: PREVIOUS FRAMES of this same animation. Continue with an identical design, scale and rendering.\n'
                if previous_out else '')
    prompt = PROMPT.format(name='Kamado Tanjiro', clip=clip, first=chunk[0] + 1, last=chunk[-1] + 1, total=len(frames),
                           previous=previous, count=count, cell=cell, intro=pose['intro'], frames='\n'.join(lines),
                           identity=data['identity'], style=data['style'], background=data['background_name'])
    prompt_path = out / 'prompts' / (job_id + '.txt')
    prompt_path.write_text(prompt, encoding='utf-8')
    references = ['output/imagegen/%s-v3/references/approved-idle-candidate.png' % args.character,
                  'output/imagegen/%s-v3/raw/%s-v3-model.png' % (args.character, args.character),
                  'output/imagegen/%s-v3/references/portrait.png' % args.character]
    if previous_out:
        references.append(previous_out)
    return dict(id=job_id, group=args.group, prompt=rel(prompt_path), out=rel(out / 'raw' / (job_id + '.png')), size='1536x1024',
                references=references,
                metadata=dict(character=args.character, clip=clip, part=index, frame_indices=chunk, overlap=overlap,
                              columns=count, rows=1, count=count, cell=[cell, 1024], layout=pose['layout']))


def active(jobs, clip, character):
    """Latest non-superseded job for each part of a clip."""
    latest = {}
    for job in jobs:
        meta = job.get('metadata', {})
        if meta.get('clip') == clip and job['id'].startswith(character + '-v3-' + clip + '-p') and not job.get('superseded_by'):
            latest[meta['part']] = job
    return latest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', default='tanjiro')
    parser.add_argument('--clips', default='')
    parser.add_argument('--redo', default='', help='clip:part,... regenerate these parts with the current rules')
    parser.add_argument('--group', default='production')
    args = parser.parse_args()
    data = spec(args.character)
    poses = read(POSES / (args.character + '.json'))['clips']
    out = production(args.character)
    jobs = read(out / 'jobs.json', [])
    added = 0
    for clip in [c for c in args.clips.split(',') if c]:
        pose = poses[clip]
        existing = active(jobs, clip, args.character)
        previous_out = None
        for index, (chunk, overlap) in enumerate(parts(len(pose['frames']), LAYOUTS[pose['layout']])):
            if index in existing:
                previous_out = existing[index]['out']
                continue
            job = make_job(args, data, pose, clip, index, chunk, overlap, previous_out)
            jobs.append(job)
            previous_out = job['out']
            added += 1
    for entry in [e for e in args.redo.split(',') if e]:
        clip, index = entry.split(':')
        index = int(index)
        pose = poses[clip]
        existing = active(jobs, clip, args.character)
        old = existing[index]
        chunk, overlap = parts(len(pose['frames']), LAYOUTS[pose['layout']])[index]
        revision = '-r%d' % (sum(1 for j in jobs if j['id'].startswith(old['id'].split('-r')[0])) )
        previous_out = existing[index - 1]['out'] if index > 0 else None
        job = make_job(args, data, pose, clip, index, chunk, overlap, previous_out, revision)
        old['superseded_by'] = job['id']
        jobs.append(job)
        added += 1
    save(out / 'jobs.json', jobs)
    print('Added', added, 'jobs;', len(jobs), 'total')


if __name__ == '__main__':
    main()
