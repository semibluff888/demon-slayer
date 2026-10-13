"""Generation progress per clip: which clips have every active sheet on disk.

Usage: python tools/art_v3/status.py [--character tanjiro] [--ready-only]
"""
import argparse

from common import ROOT, production, read


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', default='tanjiro')
    parser.add_argument('--ready-only', action='store_true')
    args = parser.parse_args()
    out = production(args.character)
    clips = {}
    for job in read(out / 'jobs.json', []):
        meta = job.get('metadata', {})
        if 'part' not in meta or job.get('superseded_by'):
            continue
        clips.setdefault(meta['clip'], []).append((ROOT / job['out']).exists())
    ready = sorted(clip for clip, done in clips.items() if all(done))
    if args.ready_only:
        print(','.join(ready))
        return
    total = sum(len(done) for done in clips.values())
    finished = sum(sum(done) for done in clips.values())
    print('%d/%d sheets, %d/%d clips ready' % (finished, total, len(ready), len(clips)))
    for clip, done in sorted(clips.items()):
        if not all(done):
            print('  %-18s %d/%d' % (clip, sum(done), len(done)))


if __name__ == '__main__':
    main()
