"""Quality report for processed v3 clips: one table per clip from imports/<clip>.json.

Per generated sheet: how its scale was found (head ruler, overlap, registration), the
resample factor relative to the approved key (0.62-1.1 passes tests/art_v3_tests.py,
1.2 for lying or rotated sheets) and the colour distance of every material before and
after the lock (locked materials must end at dE <= 4.5). Per frame: head ratio to its
sheet, height relative to the idle and every QA flag or note. Writes Markdown to
artifacts/art-v3/<id>/report-<name>.md and prints it.

Usage: python tools/art_v3/report.py --character zenitsu --clips walk,stand_light,thunder [--name pilot]
"""
import argparse

from common import ROOT, production, read, spec


def clip_report(character, clip, locked):
    record = read(production(character) / 'imports' / (clip + '.json'))
    if record is None:
        return ['### %s' % clip, '', 'not processed yet', '']
    lines = ['### %s (%d frames)' % (clip, len(record['frames'])), '']
    parts = record.get('parts', [])
    if parts:
        lines += ['| sheet | scale method | resample vs key | dE before -> after (locked) | colour shift |', '|---|---|---|---|---|']
        for part in parts:
            modes = {f.get('anchor_mode') for f in record['frames'] if f.get('part') == part['id']}
            limit = 1.2 if modes and modes <= {'lying', 'pelvis'} else 1.1
            ok = 0.62 <= part['resample_vs_idle'] <= limit
            delta = ', '.join('%s %.1f -> %.1f%s' % (name, part['palette_delta_e_before'].get(name, 0), part['palette_delta_e_after'].get(name, 0),
                                                     '' if part['palette_delta_e_after'].get(name, 0) <= 4.5 else ' (!)')
                              for name in locked if name in part['palette_delta_e_after'])
            lines.append('| %s | %s | %.3f%s | %s | %s |' % (part['id'].split('-v3-')[-1], part['scale_method'], part['resample_vs_idle'],
                                                            '' if ok else ' (!)', delta, ', '.join(sorted(part['palette_shift'])) or '-'))
        lines.append('')
    lines += ['| frame | head / sheet | height / idle | anchor | flags and notes |', '|---|---|---|---|---|']
    for frame in record['frames']:
        notes = ['**%s**' % flag for flag in frame.get('flags', [])] + frame.get('notes', [])
        lines.append('| %s | %s | %s | %s | %s |' % (frame['frame'], frame.get('ratio_to_sheet') or '-', frame.get('height_vs_idle', '-'),
                                                    frame.get('anchor_mode', '-'), '; '.join(notes) or 'ok'))
    flagged = sum(1 for frame in record['frames'] if frame.get('flags'))
    lines += ['', 'blocking flags: %d' % flagged, '']
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', required=True)
    parser.add_argument('--clips', required=True)
    parser.add_argument('--name', default='clips')
    args = parser.parse_args()
    locked = spec(args.character)['materials']['locked']
    lines = ['# %s v3 QA: %s' % (args.character, args.clips), '']
    for clip in args.clips.split(','):
        lines += clip_report(args.character, clip, locked)
    text = '\n'.join(lines)
    target = ROOT / 'artifacts/art-v3' / args.character / ('report-%s.md' % args.name)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding='utf-8')
    print(text)


if __name__ == '__main__':
    main()
